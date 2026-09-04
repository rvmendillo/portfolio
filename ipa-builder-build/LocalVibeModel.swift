import Foundation
import Combine
import LlamaSwift

struct VibePatch {
    var summary: String
    var components: [StudioComponent]
    var widget: StudioWidgetConfig?
    var variableUpdates: [String: String] = [:]
}

enum VibeModelError: LocalizedError {
    case modelMissing
    case modelDownload
    case modelLoad
    case contextCreate
    case tokenize
    case decode

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "Qwen2.5-Coder-3B is not installed yet. Download the local coding model first."
        case .modelDownload:
            return "The Qwen2.5-Coder-3B model download was incomplete or invalid."
        case .modelLoad:
            return "Qwen2.5-Coder-3B could not be loaded on this device."
        case .contextCreate:
            return "The local coding-model context could not be created."
        case .tokenize:
            return "The Swift/iOS prompt could not be tokenized."
        case .decode:
            return "Local coding-model generation failed."
        }
    }
}

enum LargeCodeModelConfig {
    static let displayName = "Qwen2.5-Coder-3B-Instruct Q4_K_M"
    static let fileName = "qwen2.5-coder-3b-instruct-q4_k_m.gguf"
    static let expectedSizeText = "~2.1 GB"
    static let minimumValidBytes: UInt64 = 1_500_000_000
    static let remoteURL = URL(string: "https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf?download=true")!

    static var modelDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Models", isDirectory: true)
    }

    static var modelURL: URL {
        modelDirectory.appendingPathComponent(fileName)
    }

    static var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: modelURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.uint64Value >= minimumValidBytes
    }
}

@MainActor
final class LargeCodeModelManager: ObservableObject {
    static let shared = LargeCodeModelManager()

    @Published var isDownloading = false
    @Published var status = LargeCodeModelConfig.isInstalled
        ? "3B Swift/iOS coding model installed"
        : "3B coding model not downloaded"
    @Published var lastError: String?

    private init() {}

    var isInstalled: Bool { LargeCodeModelConfig.isInstalled }
    var modelName: String { LargeCodeModelConfig.displayName }
    var sizeText: String { LargeCodeModelConfig.expectedSizeText }

    func downloadModel() async {
        guard !isDownloading else { return }
        isDownloading = true
        lastError = nil
        status = "Downloading \(LargeCodeModelConfig.expectedSizeText) coding model…"

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: LargeCodeModelConfig.modelDirectory, withIntermediateDirectories: true)

            let (temporaryURL, response) = try await URLSession.shared.download(from: LargeCodeModelConfig.remoteURL)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw VibeModelError.modelDownload
            }

            let attributes = try fm.attributesOfItem(atPath: temporaryURL.path)
            let bytes = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard bytes >= LargeCodeModelConfig.minimumValidBytes else {
                throw VibeModelError.modelDownload
            }

            let destination = LargeCodeModelConfig.modelURL
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: temporaryURL, to: destination)

            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = destination
            try? mutable.setResourceValues(values)

            status = "Qwen2.5-Coder-3B ready · offline"
        } catch {
            lastError = error.localizedDescription
            status = "Model download failed"
        }

        isDownloading = false
        objectWillChange.send()
    }

    func removeModel() {
        try? FileManager.default.removeItem(at: LargeCodeModelConfig.modelURL)
        status = "3B coding model not downloaded"
        lastError = nil
        objectWillChange.send()
    }
}

final class LocalVibeModel {
    static let shared = LocalVibeModel()

    private init() {}

    var modelURL: URL? {
        LargeCodeModelConfig.isInstalled ? LargeCodeModelConfig.modelURL : nil
    }

    var isInstalled: Bool { modelURL != nil }

    func propose(prompt userPrompt: String, project: StudioProject) throws -> String {
        guard let modelURL else {
            throw VibeModelError.modelMissing
        }

        llama_backend_init()
        defer { llama_backend_free() }

        let modelParams = llama_model_default_params()
        guard let model = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw VibeModelError.modelLoad
        }
        defer { llama_model_free(model) }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 4096
        contextParams.n_batch = 512

        guard let context = llama_init_from_model(model, contextParams) else {
            throw VibeModelError.contextCreate
        }
        defer { llama_free(context) }

        let current = project.components.map { component in
            let actions = component.actions
                .map { "\($0.kind.rawValue)(\($0.key)=\($0.value))" }
                .joined(separator: ",")
            return "\(component.kind.rawValue){text=\(component.text),detail=\(component.detail),actions=[\(actions)]}"
        }.joined(separator: "; ")

        let variables = project.variables
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")

        let systemPrompt = """
        You are ReyForge Native iOS Coder, a senior Swift 6, SwiftUI, UIKit and iOS 17+ engineer.
        Reason like an experienced native Apple-platform developer: use standard iOS interaction patterns,
        accessibility-friendly labels, SF Symbols, sensible forms/navigation, and compact mobile layouts.
        Translate the requested native iOS feature into ReyForge's editable UI patch DSL.

        Output ONLY valid DSL lines. Never output Markdown, prose, Swift source, comments, or code fences.

        ADD|<component kind>|<text>|<x>|<y>|<width>|<height>|<detail>
        ACTION|<last component>|<action kind>|<key>|<value>
        VARIABLE|<key>|<value>
        WIDGET|<title>|<subtitle>|<sf symbol>|<systemSmall/systemMedium/systemLarge>

        Component kinds: Text, Button, Text Field, Secure Field, Text Editor, Image,
        SF Symbol, Label, Toggle, Slider, Stepper, Picker, Date Picker, Color Picker,
        Progress View, Gauge, Divider, Spacer, Link, Menu, Navigation Link, List,
        Scroll View, VStack, HStack, ZStack, Form, Section, Capsule, Rounded Rectangle,
        Circle, Web View, Map, Share Link.

        Action kinds: Show Alert, Navigate, Set Variable, Toggle Variable, Increment,
        Decrement, Open URL, Save Locally, GET Request, Copy Text.

        Canvas size is 390x844. Keep controls in bounds and avoid overlapping them.
        Use multiple components when needed to express a complete SwiftUI-style screen.
        For authentication, forms, settings, dashboards, profiles, networking, and widgets,
        infer the expected native iOS controls and actions instead of creating placeholder text only.
        """

        let prompt = """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        Target: native Swift/SwiftUI iOS 17+
        App: \(project.name)
        Existing components: \(current.isEmpty ? "none" : current)
        Variables: \(variables.isEmpty ? "none" : variables)
        Widget enabled: \(project.widget.enabled)
        Request: \(userPrompt)<|im_end|>
        <|im_start|>assistant
        """

        let vocab = llama_model_get_vocab(model)
        let utf8Count = prompt.utf8.count
        let maxTokenCount = max(512, utf8Count * 2 + 256)
        var tokens = [llama_token](repeating: 0, count: maxTokenCount)

        let tokenCount = llama_tokenize(
            vocab,
            prompt,
            Int32(utf8Count),
            &tokens,
            Int32(maxTokenCount),
            true,
            true
        )
        guard tokenCount > 0 else {
            throw VibeModelError.tokenize
        }

        let promptTokens = Array(tokens.prefix(Int(tokenCount)))
        guard promptTokens.count < Int(contextParams.n_ctx) - 640 else {
            throw VibeModelError.tokenize
        }

        let batchCapacity = max(Int32(contextParams.n_batch), Int32(promptTokens.count + 8))
        var batch = llama_batch_init(batchCapacity, 0, 1)
        defer { llama_batch_free(batch) }

        batch.n_tokens = Int32(promptTokens.count)
        for index in 0..<promptTokens.count {
            batch.token[index] = promptTokens[index]
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            if let sequenceIDs = batch.seq_id,
               let sequenceID = sequenceIDs[index] {
                sequenceID[0] = 0
            }
            batch.logits[index] = 0
        }
        if batch.n_tokens > 0 {
            batch.logits[Int(batch.n_tokens) - 1] = 1
        }

        guard llama_decode(context, batch) == 0 else {
            throw VibeModelError.decode
        }

        var output = ""
        var currentPosition = batch.n_tokens
        let vocabSize = Int(llama_vocab_n_tokens(vocab))

        for _ in 0..<520 {
            guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else {
                throw VibeModelError.decode
            }

            var maxLogit = logits[0]
            var nextToken: llama_token = 0
            if vocabSize > 1 {
                for index in 1..<vocabSize where logits[index] > maxLogit {
                    maxLogit = logits[index]
                    nextToken = llama_token(index)
                }
            }

            if nextToken == llama_vocab_eos(vocab) {
                break
            }

            var buffer = [CChar](repeating: 0, count: 256)
            let length = llama_token_to_piece(
                vocab,
                nextToken,
                &buffer,
                Int32(buffer.count),
                0,
                false
            )

            if length > 0 {
                let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
                if let piece = String(bytes: bytes, encoding: .utf8) {
                    output += piece
                    if output.contains("<|im_end|>") {
                        break
                    }
                }
            }

            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = currentPosition
            batch.n_seq_id[0] = 1
            if let sequenceIDs = batch.seq_id,
               let sequenceID = sequenceIDs[0] {
                sequenceID[0] = 0
            }
            batch.logits[0] = 1
            currentPosition += 1

            guard llama_decode(context, batch) == 0 else {
                throw VibeModelError.decode
            }
        }

        return output
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum VibePatchParser {
    static func parse(
        _ output: String,
        fallbackPrompt: String,
        project: StudioProject
    ) -> VibePatch {
        var added: [StudioComponent] = []
        var widget: StudioWidgetConfig?
        var variables: [String: String] = [:]
        var lastComponentIndex: Int?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let parts = rawLine
                .split(separator: "|", omittingEmptySubsequences: false)
                .map(String.init)
            guard let command = parts.first?.uppercased() else { continue }

            switch command {
            case "ADD" where parts.count >= 7:
                guard let kind = StudioComponentKind(rawValue: parts[1]) else { continue }
                var component = StudioComponent.make(kind)
                component.text = parts[2]
                component.x = Double(parts[3]) ?? 195
                component.y = Double(parts[4]) ?? 120
                component.width = Double(parts[5]) ?? kind.defaultSize.width
                component.height = Double(parts[6]) ?? kind.defaultSize.height
                if parts.count > 7 {
                    component.detail = parts[7]
                }
                component.x = min(
                    max(component.width / 2, component.x),
                    390 - component.width / 2
                )
                component.y = max(component.height / 2, component.y)
                added.append(component)
                lastComponentIndex = added.count - 1

            case "ACTION" where parts.count >= 5:
                guard let index = lastComponentIndex,
                      let kind = StudioActionKind(rawValue: parts[2]) else { continue }
                added[index].actions.append(
                    .init(kind: kind, key: parts[3], value: parts[4])
                )

            case "VARIABLE" where parts.count >= 3:
                variables[parts[1]] = parts[2]

            case "WIDGET" where parts.count >= 5:
                var config = project.widget
                config.enabled = true
                config.title = parts[1]
                config.subtitle = parts[2]
                config.symbol = parts[3].isEmpty ? "sparkles" : parts[3]
                let allowed = ["systemSmall", "systemMedium", "systemLarge"]
                config.family = allowed.contains(parts[4]) ? parts[4] : "systemMedium"
                widget = config

            default:
                continue
            }
        }

        if added.isEmpty && widget == nil && variables.isEmpty {
            return heuristic(prompt: fallbackPrompt, project: project)
        }

        return VibePatch(
            summary: "Qwen2.5-Coder-3B proposed \(added.count) native component change(s).",
            components: added,
            widget: widget,
            variableUpdates: variables
        )
    }

    static func heuristic(prompt: String, project: StudioProject) -> VibePatch {
        let lowercased = prompt.lowercased()
        var components: [StudioComponent] = []
        var widget: StudioWidgetConfig?

        func append(_ kind: StudioComponentKind, _ text: String, y: Double) {
            var component = StudioComponent.make(kind, x: 195, y: y)
            component.text = text
            if kind == .button {
                component.width = 300
            }
            components.append(component)
        }

        if lowercased.contains("login") || lowercased.contains("sign in") {
            append(.text, "Welcome", y: 120)
            append(.textField, "Email", y: 210)
            append(.secureField, "Password", y: 280)
            var button = StudioComponent.make(.button, x: 195, y: 370)
            button.text = "Sign In"
            button.width = 300
            button.actions = [
                .init(kind: .showAlert, key: "Success", value: "Signed in")
            ]
            components.append(button)
        } else if lowercased.contains("settings") {
            append(.text, "Settings", y: 90)
            append(.toggle, "Notifications", y: 180)
            append(.toggle, "Use Face ID", y: 250)
            append(.picker, "Theme", y: 330)
            append(.button, "Save", y: 420)
        } else if lowercased.contains("widget") {
            var config = project.widget
            config.enabled = true
            config.title = project.name
            config.subtitle = "Built with ReyForge"
            widget = config
        } else if lowercased.contains("form") {
            append(.textField, "Name", y: 130)
            append(.textField, "Email", y: 205)
            append(.textEditor, "Message", y: 330)
            append(.button, "Submit", y: 470)
        } else {
            append(.text, project.name, y: 100)
            append(.button, "Continue", y: 190)
        }

        return VibePatch(
            summary: "Applied an offline fallback patch while keeping the project editable.",
            components: components,
            widget: widget
        )
    }
}
