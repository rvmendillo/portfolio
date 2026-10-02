import SwiftUI
import UniformTypeIdentifiers

enum ModelFiles {
    static func directory() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    static func url(for name: String) -> URL? {
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
              let root = try? directory() else { return nil }
        let result = root.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: result.path) ? result : nil
    }
    static func importModel(_ source: URL) throws -> String {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 1024, size <= 2_000_000_000,
              source.pathExtension.lowercased() == "gguf" else {
            throw StudioError.message("Choose a single .gguf model below 2 GB. Smaller quantized models use less memory.")
        }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else { throw StudioError.message("This file is not a GGUF model.") }
        let root = try directory()
        let name = UUID().uuidString + ".gguf"
        let destination = root.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var mutable = destination; try mutable.setResourceValues(values)
            return name
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
}

struct SettingsView: View {
    @AppStorage("aiEngine") private var engine = AIEngine.gguf.rawValue
    @AppStorage("useMetal") private var useMetal = true
    @AppStorage("modelFile") private var modelFile = ""
    @AppStorage("modelDisplayName") private var modelName = ""
    @State private var importing = false
    @State private var copying = false
    @State private var error: String?
    @State private var removing = false
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "square.grid.2x2.fill").font(.largeTitle).foregroundStyle(Palette.mint)
                    Text("ReyWidgets Studio").font(.title2.weight(.semibold))
                    Text("Little windows. Limitless ideas.").foregroundStyle(Palette.muted)
                    Text("Version 1.0 • iOS 17+").font(.caption).foregroundStyle(Palette.muted)
                }.padding(.vertical, 12)
            }
            Section("Local intelligence") {
                Picker("Default engine", selection: $engine) { ForEach(AIEngine.allCases) { Text($0.label).tag($0.rawValue) } }
                LabeledContent("Apple model") { Text(LocalAI.appleStatus).font(.caption).multilineTextAlignment(.trailing) }
                Text("Apple's on-device model requires compatible Apple Intelligence hardware and iOS 26+. GGUF inference uses llama.cpp directly on your iPhone and does not need Apple Intelligence or JIT.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Section("Your GGUF model") {
                if modelFile.isEmpty { Text("No model imported").foregroundStyle(Palette.muted) }
                else {
                    Label(modelName, systemImage: "internaldrive").font(.subheadline)
                    if let url = ModelFiles.url(for: modelFile),
                       let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                Button("Import .gguf from Files", systemImage: "square.and.arrow.down") { importing = true }.disabled(copying)
                if copying { ProgressView("Copying model…") }
                Toggle("Use Metal acceleration", isOn: $useMetal)
                Text("Use a small instruction-tuned model with an embedded chat template. A 0.5B–1.5B Q4 model is a sensible starting size; available RAM determines what your phone can load. Model weights are not included.")
                    .font(.caption).foregroundStyle(Palette.muted)
                if !modelFile.isEmpty { Button("Remove imported model", role: .destructive) { removing = true }.disabled(copying) }
            }
            Section("Make it yours") {
                NavigationLink("Getting started", destination: HelpView())
                LabeledContent("Networking", value: "Your configured APIs only")
                Text("API header values stay in the shared Keychain. Exported projects contain code, URLs, request bodies and sample data, but omit saved headers. HTML runs with external network access disabled.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Section("Open-source runtime") {
                Text("llama.cpp • ggml authors • MIT license").font(.caption)
                Link("View runtime source and license", destination: URL(string: "https://github.com/ggml-org/llama.cpp/tree/b10809")!)
            }
        }.navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
                switch result {
                case .failure(let failure): error = failure.localizedDescription
                case .success(let url):
                    copying = true
                    Task {
                        defer { copying = false }
                        do {
                            let imported = try await Task.detached(priority: .userInitiated) { try ModelFiles.importModel(url) }.value
                            let previous = ModelFiles.url(for: modelFile)
                            modelFile = imported; modelName = url.lastPathComponent
                            if let previous { try? FileManager.default.removeItem(at: previous) }
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .confirmationDialog("Remove this model from the device?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove model", role: .destructive) {
                    if let url = ModelFiles.url(for: modelFile) {
                        do { try FileManager.default.removeItem(at: url); modelFile = ""; modelName = "" }
                        catch { self.error = error.localizedDescription }
                    } else { modelFile = ""; modelName = "" }
                }
            }
            .alert("Model import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("Add your first Home Screen widget") {
                Text("1. Open a design in Studio. Customize it, run the preview, and tap Publish.")
                Text("2. Touch and hold an empty part of your iPhone Home Screen. Open the widget gallery from Edit → Add Widget (or + on older iOS versions).")
                Text("3. Search for ReyWidgets. Pick small, medium or large and add it.")
                Text("4. Touch and hold the added widget → Edit Widget → Design. Choose your saved design.")
            }
            Section("Native and HTML") {
                Text("Native designs are drawn with SwiftUI. Edit the form or the layout JSON. Native code uses supported layout fields; arbitrary Swift source is edited and compiled in Xcode.")
                Text("HTML designs run in the in-app WebKit canvas. Publish creates one image per widget size. Home Screen HTML is a snapshot: scripts, animations and HTML buttons do not keep running there. Tap it to reopen the editor.")
                Text("Preview dimensions are design presets. iOS widget dimensions vary by device; the final image scales to fit. Re-publish whenever HTML or its API data changes.")
            }
            Section("Connect data") {
                Text("Enter your API's final HTTPS JSON URL. Supply GET or a read-only POST request and optional JSON headers. Tap Test API to inspect the response, then enable Use API when publishing.")
                Text("Native text: {{/items/0/title}}. HTML text: <span data-bind=\"/items/0/title\"></span>. JavaScript: widget.get('/items/0/title', 'No title').")
                Text("Use ~1 for a slash inside a JSON key and ~0 for a tilde. Missing values show —. Connect one endpoint per widget; use an API that aggregates data if you need multiple sources.")
                Text("Native API refresh follows the interval you choose, subject to iOS scheduling. It is not a real-time feed. On network errors, a previous successful response is retained and marked cached.")
                Text("Headers can contain secrets; project URLs, request bodies and sample JSON are included in exports. Check them before sharing a project. Native widgets can display private data visibly on the Home Screen.")
            }
            Section("Generate offline") {
                Text("Choose Apple on-device model if Settings says Ready. Otherwise import a compatible instruction GGUF from Files, then choose Imported GGUF model in AI. No cloud fallback is used.")
                Text("Describe layout, colors and any API data paths. Review the generated code, apply it, run it, then publish. Small local models may need simpler prompts or manual corrections.")
                Text("Models load only during generation and unload afterward. Cancel is checked between decoding batches. Import checks the GGUF header; architecture compatibility is checked when loading.")
            }
            Section("If the widget is missing") {
                Text("Install the app as a normal iOS app with its embedded widget extension. Both must be signed for the same App Group and Keychain group. Launch the app once before looking in the widget gallery.")
                Text("A hosted app inside LiveContainer cannot register its own system widget extension. Home Screen installation and widget placement are managed by iOS.")
            }
        }.navigationTitle("Getting started").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
