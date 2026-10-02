import Foundation
import llama
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIEngine: String, CaseIterable, Identifiable {
    case apple, gguf
    var id: String { rawValue }
    var label: String { self == .apple ? "Apple on-device model" : "Imported GGUF model" }
}

struct GeneratedWidget: Codable {
    var html: String
    var css: String
    var javascript: String
    static func parse(_ raw: String) throws -> Self {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let end = text.range(of: "```", options: .backwards) { text = String(text[..<end.lowerBound]) }
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw StudioError.message("The model did not return a widget. Try a shorter, simpler request.")
        }
        let result = try JSONDecoder().decode(Self.self, from: Data(text[start...end].utf8))
        guard !result.html.isEmpty, result.html.utf8.count + result.css.utf8.count + result.javascript.utf8.count <= 200_000 else {
            throw StudioError.message("The generated widget is empty or too large.")
        }
        return result
    }
}

enum LocalAI {
    static let instructions = """
    Create a compact iOS widget using HTML, CSS and JavaScript. Return only a JSON object with exactly
    three string keys: html, css, javascript. No markdown or explanation. HTML is a body fragment.
    Use inline styles or the css field. No external URLs, libraries, fetch, iframes, forms, or images
    other than inline SVG. Fit within 170x170, 364x170 and 364x382 using responsive CSS.
    Available JavaScript: widget.data (JSON), widget.size, widget.width, widget.height,
    widget.get('/json/pointer', fallback). For simple text use data-bind="/json/pointer".
    JavaScript runs after DOMContentLoaded. Set widget.ready to a Promise for asynchronous computation.
    Prefer under 350 words of code. Use readable typography and generous spacing. Output valid JSON.
    """

    static var appleStatus: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Ready • runs on this device"
            case .unavailable(let reason): return "Unavailable on this device: \(reason)"
            @unknown default: return "Model availability is unknown"
            }
        }
        #endif
        return "Requires iOS 26 and an Apple Intelligence compatible device"
    }

    static func generate(prompt: String, engine: AIEngine, modelURL: URL?, useGPU: Bool) async throws -> GeneratedWidget {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 1500 else {
            throw StudioError.message("Describe a widget in 1–1500 characters.")
        }
        let raw: String
        switch engine {
        case .apple:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard case .available = SystemLanguageModel.default.availability else { throw StudioError.message(appleStatus) }
                let session = LanguageModelSession(instructions: instructions)
                raw = try await session.respond(to: prompt).content
            } else { throw StudioError.message(appleStatus) }
            #else
            throw StudioError.message(appleStatus)
            #endif
        case .gguf:
            guard let modelURL else { throw StudioError.message("Import an instruction-tuned .gguf model in Settings first.") }
            raw = try await GGUFEngine.shared.generate(path: modelURL.path, prompt: prompt, useGPU: useGPU)
        }
        try Task.checkCancellation()
        return try GeneratedWidget.parse(raw)
    }
}

// Actor serialization prevents simultaneous model loads and keeps inference off the UI actor.
actor GGUFEngine {
    static let shared = GGUFEngine()
    private var initialized = false

    func generate(path: String, prompt: String, useGPU: Bool) throws -> String {
        try Task.checkCancellation()
        if !initialized { llama_backend_init(); initialized = true }
        var params = llama_model_default_params()
        params.n_gpu_layers = useGPU ? 99 : 0
        #if targetEnvironment(simulator)
        params.n_gpu_layers = 0
        #endif
        guard let model = llama_model_load_from_file(path, params) else {
            throw StudioError.message("Cannot load this GGUF. Check the model format, available memory, or turn off Metal in Settings.")
        }
        defer { llama_model_free(model) }
        try Task.checkCancellation()
        guard let vocab = llama_model_get_vocab(model) else { throw StudioError.message("This model has no vocabulary.") }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 4096; contextParams.n_batch = 256; contextParams.n_ubatch = 256
        contextParams.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))
        contextParams.n_threads_batch = contextParams.n_threads
        guard let context = llama_init_from_model(model, contextParams) else {
            throw StudioError.message("Not enough memory for this model. Import a smaller quantized model.")
        }
        defer { llama_free(context) }

        // Keep C strings alive for the complete chat-template call.
        let systemRole = strdup("system")!, userRole = strdup("user")!
        let systemText = strdup(LocalAI.instructions)!, userText = strdup(prompt)!
        defer { free(systemRole); free(userRole); free(systemText); free(userText) }
        let messages = [llama_chat_message(role: UnsafePointer(systemRole), content: UnsafePointer(systemText)),
                        llama_chat_message(role: UnsafePointer(userRole), content: UnsafePointer(userText))]
        guard let template = llama_model_chat_template(model, nil) else {
            throw StudioError.message("Use an instruction model with an embedded chat template.")
        }
        var formatted = [CChar](repeating: 0, count: 32_768)
        let formattedCapacity = Int32(formatted.count)
        let formattedCount = messages.withUnsafeBufferPointer { buffer in
            llama_chat_apply_template(template, buffer.baseAddress, buffer.count, true, &formatted, formattedCapacity)
        }
        guard formattedCount > 0, Int(formattedCount) < formatted.count else {
            throw StudioError.message("This chat template is unsupported. Try a Qwen2.5 or Llama instruction GGUF.")
        }
        var tokens = [llama_token](repeating: 0, count: 4096)
        let tokenCount = llama_tokenize(vocab, &formatted, formattedCount, &tokens, 4096, true, true)
        guard tokenCount > 0, tokenCount < 2800 else {
            throw StudioError.message("The prompt is too long for the local model context. Shorten it.")
        }
        tokens = Array(tokens.prefix(Int(tokenCount)))
        for offset in stride(from: 0, to: tokens.count, by: 256) {
            try Task.checkCancellation()
            var chunk = Array(tokens[offset..<min(offset + 256, tokens.count)])
            let status = chunk.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
            }
            guard status == 0 else { throw StudioError.message("Local model could not process the prompt (\(status)).") }
        }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw StudioError.message("Could not create the model sampler.")
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))
        var output = Data()
        for _ in 0..<min(1200, 4096 - Int(tokenCount) - 1) {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                return String(decoding: output, as: UTF8.self)
            }
            var piece = [CChar](repeating: 0, count: 256)
            var length = llama_token_to_piece(vocab, token, &piece, 256, 0, false)
            if length < 0 {
                let capacity = -length
                piece = [CChar](repeating: 0, count: Int(capacity))
                length = llama_token_to_piece(vocab, token, &piece, capacity, 0, false)
            }
            guard length >= 0, Int(length) <= piece.count else { throw StudioError.message("Model token decoding failed.") }
            output.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            let status = withUnsafeMutablePointer(to: &token) {
                llama_decode(context, llama_batch_get_one($0, 1))
            }
            guard status == 0 else { throw StudioError.message("Local model generation failed (\(status)).") }
        }
        // A truncated JSON result is never silently published.
        let raw = String(decoding: output, as: UTF8.self)
        if (try? GeneratedWidget.parse(raw)) != nil { return raw }
        throw StudioError.message("The model reached its output limit. Ask for a simpler widget.")
    }
}
