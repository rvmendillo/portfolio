import SwiftUI
import UniformTypeIdentifiers

struct ProjectFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct EditorView: View {
    @EnvironmentObject private var studio: StudioModel
    @StateObject private var editor: EditorModel
    @State private var size: WidgetSize = .medium
    @State private var section = 0
    @State private var codeTab = 0
    @State private var live = false
    @State private var showHelp = false
    @State private var exporting = false
    @State private var exportFile = ProjectFile(data: Data())
    @AppStorage("aiEngine") private var engineRaw = AIEngine.gguf.rawValue
    @AppStorage("useMetal") private var useMetal = true
    @AppStorage("modelFile") private var modelFile = ""
    init(document: WidgetDocument) { _editor = StateObject(wrappedValue: EditorModel(document)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                Picker("Workspace", selection: $section) {
                    Text("Design").tag(0); Text("Code").tag(1); Text("API").tag(2); Text("AI").tag(3)
                }.pickerStyle(.segmented)
                Group {
                    switch section {
                    case 0: designPanel
                    case 1: codePanel
                    case 2: apiPanel
                    default: aiPanel
                    }
                }.disabled(editor.busy)
                if let message = editor.message {
                    Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(Palette.muted)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                }
                if editor.busy {
                    HStack { ProgressView(); Text("Working on your widget…").font(.caption); Spacer(); Button("Cancel") { editor.cancel() } }
                }
                HStack(spacing: 12) {
                    Button("Run preview", systemImage: "play.fill") { editor.runPreview(live: live, store: studio.store) }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Button("Publish", systemImage: "square.and.arrow.up") { editor.publish(studio: studio) }
                        .buttonStyle(.borderedProminent).foregroundStyle(.black).frame(maxWidth: .infinity)
                }.disabled(editor.busy)
                Text(editor.document.mode == .html ? "Publish captures all three sizes. Reopen and publish again to update HTML or its API data." : "Publish saves the design and requests an update. iOS chooses when background API refreshes run.")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }.padding(18)
        }.background(Palette.background)
            .navigationTitle(editor.document.name).navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(editor.busy)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Save project", systemImage: "square.and.arrow.down") { editor.save(studio: studio) }
                        Button("Export project", systemImage: "square.and.arrow.up") {
                            do { try editor.document.validate(); exportFile = ProjectFile(data: try editor.document.exportData()); exporting = true }
                            catch { editor.error = error.localizedDescription }
                        }
                        Button("How widgets work", systemImage: "questionmark.circle") { showHelp = true }
                    } label: { Image(systemName: "ellipsis.circle") }.disabled(editor.busy)
                }
            }
            .sheet(isPresented: $showHelp) { NavigationStack { HelpView() } }
            .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json,
                          defaultFilename: editor.document.name.replacingOccurrences(of: "/", with: "_") + ".reywidget") { result in
                if case .failure(let error) = result { editor.error = error.localizedDescription }
            }
            .alert("Check your widget", isPresented: Binding(get: { editor.error != nil }, set: { if !$0 { editor.error = nil } })) {
                Button("OK", role: .cancel) { editor.error = nil }
            } message: { Text(editor.error ?? "") }
            .onDisappear { editor.cancel() }
            .onChange(of: section) { _, new in if new == 2 { editor.loadHeaders() } }
            .onChange(of: editor.apiResult) { _, _ in live = true }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            HStack {
                Text("CANVAS PREVIEW").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                Spacer()
                Text(live ? "CACHED API" : "SAMPLE").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            GeometryReader { proxy in
                let scale = min(1, proxy.size.width / size.width)
                Group {
                    if editor.previewDocument.mode == .native {
                        NativeWidgetView(design: editor.previewDocument.native, data: editor.previewData, compact: size == .small, large: size == .large)
                    } else {
                        HTMLPreview(page: HTMLRuntime.page(editor.previewDocument, data: editor.previewData, size: size))
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .scaleEffect(scale, anchor: .top)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }.frame(height: size.height)
            Picker("Widget size", selection: $size) { ForEach(WidgetSize.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                .pickerStyle(.segmented)
            Toggle("Use cached API response for preview", isOn: $live).font(.caption)
                .onChange(of: live) { _, value in editor.runPreview(live: value, store: studio.store) }
        }.padding(14).background(Palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
    }

    private var designPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            TextField("Widget name", text: $editor.document.name).textFieldStyle(.roundedBorder)
            Picker("Renderer", selection: $editor.document.mode) { ForEach(WidgetMode.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
            if editor.document.mode == .native {
                Picker("Layout", selection: $editor.document.native.layout) { ForEach(NativeDesign.Layout.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                input("Title", text: $editor.document.native.title)
                input("Value", text: $editor.document.native.value)
                input("Subtitle", text: $editor.document.native.subtitle)
                input("Footer", text: $editor.document.native.footer)
                input("SF Symbol", text: $editor.document.native.symbol)
                HStack {
                    input("Background", text: $editor.document.native.background)
                    input("Accent", text: $editor.document.native.accent)
                }
                input("Text color", text: $editor.document.native.foreground)
                if editor.document.native.layout == .progress {
                    Slider(value: $editor.document.native.progress, in: 0...1) { Text("Progress") }
                    Text("\(Int(editor.document.native.progress * 100))% complete").font(.caption).foregroundStyle(Palette.muted)
                }
                if editor.document.native.layout == .list {
                    ForEach(editor.document.native.rows.indices, id: \.self) { index in
                        HStack {
                            TextField("Row", text: $editor.document.native.rows[index]).textFieldStyle(.roundedBorder)
                            Button { editor.document.native.rows.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        }
                    }
                    Button("Add row", systemImage: "plus") { editor.document.native.rows.append("New intention") }.disabled(editor.document.native.rows.count >= 30)
                }
            } else {
                Label("Shape your canvas in Code, or describe it in AI.", systemImage: "curlybraces").foregroundStyle(Palette.muted)
                Button("Open HTML editor") { section = 1 }
            }
        }.onChange(of: editor.document.native) { _, _ in editor.syncCodeFromDesign() }
    }

    private var codePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editor.document.mode == .native {
                Text("Native layout JSON").font(.headline)
                Text("Edit the structure and apply it. Text fields support {{/json/pointer}} API bindings.").font(.caption).foregroundStyle(Palette.muted)
                CodeField(text: $editor.nativeCode, label: "Native JSON")
                Button("Apply native JSON") { editor.applyNativeCode() }.buttonStyle(.bordered)
            } else {
                Picker("Source", selection: $codeTab) { Text("HTML").tag(0); Text("CSS").tag(1); Text("JavaScript").tag(2) }.pickerStyle(.segmented)
                if codeTab == 0 { CodeField(text: $editor.document.html, label: "HTML") }
                else if codeTab == 1 { CodeField(text: $editor.document.css, label: "CSS") }
                else { CodeField(text: $editor.document.javascript, label: "JavaScript") }
                Text("Use widget.data or widget.get('/path'). Add data-bind=\"/path\" to fill text automatically. Connect your API in the API tab.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }

    private var apiPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Use API when publishing", isOn: $editor.document.api.enabled)
            input("HTTPS endpoint", text: $editor.document.api.url)
            Picker("Method", selection: $editor.document.api.method) { Text("GET").tag("GET"); Text("POST").tag("POST") }.pickerStyle(.segmented)
            if editor.document.api.method == "POST" { CodeField(text: $editor.document.api.body, label: "Request body", height: 120) }
            DisclosureGroup("Request headers • stored in Keychain") {
                CodeField(text: $editor.rawHeaders, label: "Headers JSON", height: 130).privacySensitive()
                Text("Example: {\"Authorization\":\"Bearer YOUR_TOKEN\"}").font(.caption2).foregroundStyle(Palette.muted)
            }.disabled(!editor.headersLoaded)
            Stepper("Refresh: \(editor.document.api.refreshMinutes) min", value: $editor.document.api.refreshMinutes, in: 15...1440, step: 15)
            Text("Native widgets repeat this request on an iOS-controlled schedule. Use a read-only endpoint. HTML data updates when you publish.").font(.caption).foregroundStyle(Palette.muted)
            Button("Test API & preview response", systemImage: "antenna.radiowaves.left.and.right") { editor.testAPI(store: studio.store) }
                .buttonStyle(.bordered).disabled(editor.document.api.url.isEmpty)
            DisclosureGroup("Last response") { Text(editor.apiResult).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            DisclosureGroup("Sample JSON • works offline") { CodeField(text: $editor.document.sampleJSON, label: "Sample JSON", height: 180) }
            Text("Map values with JSON Pointer: {{/current/temperature_2m}} in native text, or data-bind=\"/current/temperature_2m\" in HTML.")
                .font(.caption).foregroundStyle(Palette.muted)
        }
    }

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Imagine it. Build it here.", systemImage: "sparkles").font(.title3.weight(.semibold))
            Picker("Model", selection: $engineRaw) { ForEach(AIEngine.allCases) { Text($0.label).tag($0.rawValue) } }
            Text(engineRaw == AIEngine.apple.rawValue ? LocalAI.appleStatus : (modelFile.isEmpty ? "Import a GGUF model in Settings to get started." : "GGUF ready • runs on this device"))
                .font(.caption).foregroundStyle(Palette.muted)
            TextEditor(text: $editor.prompt).frame(height: 140).padding(8)
                .scrollContentBackground(.hidden).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            Button("Generate HTML widget", systemImage: "sparkles") {
                editor.generate(engine: AIEngine(rawValue: engineRaw) ?? .gguf,
                                modelURL: ModelFiles.url(for: modelFile), useGPU: useMetal)
            }.buttonStyle(.borderedProminent).foregroundStyle(.black)
            Text("Generation stays on this device. Your API headers and response data are never included in the prompt. Name any data paths the design should use.")
                .font(.caption).foregroundStyle(Palette.muted)
            if let generated = editor.generated {
                Text("Review your AI draft").font(.headline)
                DisclosureGroup("HTML") { source(generated.html) }
                DisclosureGroup("CSS") { source(generated.css) }
                DisclosureGroup("JavaScript") { source(generated.javascript) }
                HStack {
                    Button("Apply to editor") { editor.applyGenerated(); section = 1 }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                    Button("Discard", role: .destructive) { editor.generated = nil }
                }
            }
        }
    }
    private func source(_ value: String) -> some View { Text(value).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
    private func input(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted)
            TextField(label, text: text).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
}

struct CodeField: View {
    @Binding var text: String
    let label: String
    var height: CGFloat = 300
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label).foregroundStyle(Palette.mint)
                Spacer()
                Text("\(text.components(separatedBy: "\n").count) lines · \(text.utf8.count) B").foregroundStyle(Palette.muted)
            }.font(.system(size: 9, design: .monospaced)).padding(12)
            PlainCodeEditor(text: $text, label: label + " code editor").frame(height: height)
        }.background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

// Avoid smart punctuation changing executable code while it is typed on iOS.
struct PlainCodeEditor: UIViewRepresentable {
    @Binding var text: String
    var label: String
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(binding: $text) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear; view.textColor = .white
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.autocapitalizationType = .none; view.autocorrectionType = .no; view.spellCheckingType = .no
        view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no
        view.keyboardDismissMode = .interactive
        view.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 16, right: 10)
        let bar = UIToolbar(); bar.sizeToFit()
        context.coordinator.view = view
        var items: [UIBarButtonItem] = []
        for (index, title) in ["Tab", "{}", "[]", "<>", ";"].enumerated() {
            let item = UIBarButtonItem(title: title, style: .plain, target: context.coordinator, action: #selector(Coordinator.insert(_:)))
            item.tag = index; items.append(item)
        }
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
        items.append(UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.done)))
        bar.items = items; view.inputAccessoryView = bar
        view.text = text; view.accessibilityLabel = label
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.binding = $text
        view.isEditable = enabled; view.accessibilityLabel = label
        if view.text != text {
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var binding: Binding<String>
        weak var view: UITextView?
        init(binding: Binding<String>) { self.binding = binding }
        func textViewDidChange(_ textView: UITextView) { binding.wrappedValue = textView.text }
        @objc func insert(_ item: UIBarButtonItem) {
            view?.insertText(["  ", "{}", "[]", "<>", ";"][item.tag])
        }
        @objc func done() { view?.resignFirstResponder() }
    }
}
