import SwiftUI

private struct TerminalLine: Identifiable { let id = UUID(); let text: String; let command: Bool }

struct NativeTerminalView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var command = ""
    @State private var language = "Python"
    @State private var code = "print(\"Hello from native SwiftUI\")\nprint(6 * 7)"
    @State private var codeOutput = "Ready."
    @State private var lines = [TerminalLine(text: "Rey Portfolio Native [Version 1.0]", command: false), TerminalLine(text: "Safe local terminal. Type 'help' for commands.", command: false)]
    let languages = ["Python", "JavaScript", "Java", "C++"]
    var body: some View {
        VStack(spacing: 10) {
            Picker("Language", selection: $language) { ForEach(languages, id: \.self) { Text($0) } }.pickerStyle(.segmented).padding(.horizontal, 12)
            ScrollViewReader { proxy in ScrollView { LazyVStack(alignment: .leading, spacing: 6) { ForEach(lines) { line in Text(line.text).font(.system(.caption, design: .monospaced)).foregroundStyle(line.command ? .cyan : .white.opacity(0.82)).frame(maxWidth: .infinity, alignment: .leading).id(line.id) } }.padding(13) }.background(Color(hex: "050B14")).clipShape(RoundedRectangle(cornerRadius: 14)).onChange(of: lines.count) { _ in if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) } } }
            HStack { Text("PS native>").font(.caption.monospaced()).foregroundStyle(.cyan); TextField("command", text: $command).textInputAutocapitalization(.never).autocorrectionDisabled().font(.caption.monospaced()).onSubmit(runCommand); Button(action: runCommand) { Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(theme.accent) } }.padding(10).background(Color(hex: "07111E"), in: RoundedRectangle(cornerRadius: 13))
            DisclosureGroup("Safe code runner") { VStack(spacing: 8) { TextEditor(text: $code).font(.system(.caption, design: .monospaced)).frame(minHeight: 110).scrollContentBackground(.hidden).padding(7).background(Color(hex: "07111E"), in: RoundedRectangle(cornerRadius: 10)); HStack { Button("Run locally", systemImage: "play.fill") { codeOutput = SafeCodeRuntime.run(code, language: language) }.buttonStyle(.borderedProminent).tint(theme.accent); Spacer() }; Text(codeOutput).font(.system(.caption2, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(9).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9)) } }.font(.subheadline.bold())
        }.padding(13)
    }
    private func runCommand() { let clean = String(command.prefix(1_000)); guard !clean.trimmingCharacters(in: .whitespaces).isEmpty else { return }; lines.append(TerminalLine(text: "PS native> \(clean)", command: true)); let result = NativeCommandEngine.execute(clean, theme: theme); if result == "__CLEAR__" { lines.removeAll() } else { lines.append(TerminalLine(text: result, command: false)) }; command = "" }
}

struct NativeIDEView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var selected = "main.py"
    @State private var language = "Python"
    @State private var editor = IDEContent.main
    @State private var output = "Process ready."
    private let files = ["main.py", "agent.py", "gui.yml"]
    var body: some View {
        VStack(spacing: 0) {
            HStack { Menu { ForEach(files, id: \.self) { file in Button(file) { selected = file; editor = IDEContent.value(for: file); language = file.hasSuffix(".yml") ? "Python" : "Python" } } } label: { Label(selected, systemImage: "folder") }; Spacer(); Picker("Runtime", selection: $language) { ForEach(["Python", "Java", "C++", "JavaScript"], id: \.self) { Text($0) } }.frame(width: 125); Button { output = selected.hasSuffix(".yml") ? "GUI YAML validated. Open GUI Designer to render it." : SafeCodeRuntime.run(editor, language: language) + "\n\nProcess finished with exit code 0" } label: { Image(systemName: "play.fill") }.buttonStyle(.borderedProminent).tint(theme.accent) }.padding(10).background(.ultraThinMaterial)
            HStack(spacing: 0) {
                Text(lineNumbers).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).padding(10).frame(maxHeight: .infinity, alignment: .topTrailing).background(.black.opacity(0.2))
                TextEditor(text: $editor).font(.system(.caption, design: .monospaced)).scrollContentBackground(.hidden).padding(5).background(Color(hex: "07101B"))
            }
            VStack(alignment: .leading, spacing: 5) { HStack { Text("RUN").font(.caption2.bold()).foregroundStyle(theme.secondary); Spacer(); Button("Clear") { output = "" }.font(.caption) }; ScrollView { Text(output).font(.system(.caption2, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) } }.frame(height: 135).padding(10).background(.black.opacity(0.28))
        }
    }
    private var lineNumbers: String { (1...max(1, editor.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)).map(String.init).joined(separator: "\n") }
}

private enum IDEContent {
    static let main = "name = \"Rey\"\nskills = [\"Java\", \"Python\", \"Angular\", \"AI\"]\n\nprint(\"Hello from Rey Portfolio Native\")\nprint(6 * 7)"
    static let agent = "class LocalAgent:\n    def answer(self, question):\n        return \"On-device answer: \" + question\n\nprint(\"Native local AI ready\")"
    static let gui = NativeTranspiler.samples["GUI YAML"] ?? ""
    static func value(for file: String) -> String { file == "agent.py" ? agent : file == "gui.yml" ? gui : main }
}

struct NativeTranspilerView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var input = "Python"
    @State private var target = "Java"
    @State private var customPrint = "show"
    @State private var source = NativeTranspiler.samples["Python"] ?? ""
    @State private var output = ""
    let inputs = ["Python", "HumanCode EN", "HumanCode FIL", "GUI YAML"]
    let targets = ["Java", "Java Swing", "C++", "Python", "Tkinter", "PyQt", "Kivy"]
    var body: some View {
        VStack(spacing: 10) {
            HStack { Picker("Input", selection: $input) { ForEach(inputs, id: \.self) { Text($0) } }; Picker("Target", selection: $target) { ForEach(targets, id: \.self) { Text($0) } } }.pickerStyle(.menu).padding(.horizontal, 10)
            HStack { TextField("Custom print keyword", text: $customPrint).textInputAutocapitalization(.never).autocorrectionDisabled().font(.caption.monospaced()); Button("Sample") { source = NativeTranspiler.samples[input] ?? ""; compile() }; Button("Transpile", systemImage: "bolt.fill", action: compile).buttonStyle(.borderedProminent).tint(theme.accent) }.padding(.horizontal, 10)
            VStack(spacing: 6) { HStack { Text("INPUT"); Spacer(); Text("Offline compiler") }.font(.caption2.bold()).foregroundStyle(theme.secondary); TextEditor(text: $source).font(.system(.caption, design: .monospaced)).scrollContentBackground(.hidden).padding(6).background(Color(hex: "07111D"), in: RoundedRectangle(cornerRadius: 10)) }.frame(maxHeight: .infinity).padding(.horizontal, 10)
            VStack(spacing: 6) { HStack { Text("OUTPUT"); Spacer(); ShareLink(item: output) { Label("Share", systemImage: "square.and.arrow.up") } }.font(.caption2.bold()).foregroundStyle(theme.secondary); ScrollView([.horizontal, .vertical]) { Text(output).font(.system(.caption, design: .monospaced)).foregroundStyle(.mint).frame(maxWidth: .infinity, alignment: .leading) }.padding(10).background(Color(hex: "061019"), in: RoundedRectangle(cornerRadius: 10)) }.frame(maxHeight: .infinity).padding([.horizontal, .bottom], 10)
        }.onAppear(perform: compile).onChange(of: input) { value in source = NativeTranspiler.samples[value] ?? ""; compile() }.onChange(of: target) { _ in compile() }
    }
    private func compile() { output = NativeTranspiler.compile(source: source, input: input, target: target, customPrint: customPrint) }
}

private struct ChatMessage: Identifiable { let id = UUID(); let user: Bool; let text: String }
struct NativeAssistantView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var input = ""
    @State private var messages = [ChatMessage(user: false, text: "Hello. Ask about Rey’s experience, projects, skills, Portfolio OS, or request a Java or Python example.")]
    var body: some View {
        VStack(spacing: 10) {
            HStack { ZStack { RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)); Image(systemName: "sparkles").font(.title2) }.frame(width: 52, height: 52); VStack(alignment: .leading) { Text("RLAI Native").font(.headline); Text("Offline retrieval · no remote endpoint").font(.caption).foregroundStyle(theme.secondary) }; Spacer(); Circle().fill(.green).frame(width: 8, height: 8) }.padding(.horizontal, 14)
            ScrollViewReader { proxy in ScrollView { LazyVStack(spacing: 10) { ForEach(messages) { message in HStack { if message.user { Spacer(minLength: 45) }; Text(message.text).font(.subheadline).padding(12).background(message.user ? theme.accent.opacity(0.22) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)).frame(maxWidth: 520, alignment: message.user ? .trailing : .leading); if !message.user { Spacer(minLength: 45) } }.id(message.id) } }.padding(.horizontal, 12) }.onChange(of: messages.count) { _ in if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } } }
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(["Summarize Rey’s experience", "Explain Skyler", "Write a Java example"], id: \.self) { item in Button(item) { ask(item) }.font(.caption).buttonStyle(.bordered) } }.padding(.horizontal, 12) }
            HStack { TextField("Message the local assistant", text: $input, axis: .vertical).lineLimit(1...4).onSubmit { ask(input) }; Button { ask(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty) }.padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17)).padding(12)
        }.padding(.top, 12)
    }
    private func ask(_ value: String) { let clean = String(value.prefix(1_200)).trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return }; messages.append(ChatMessage(user: true, text: clean)); input = ""; let answer = NativeLocalAI.answer(clean); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { messages.append(ChatMessage(user: false, text: answer)) } }
}

enum NativeLocalAI {
    static func answer(_ question: String) -> String {
        let value = question.lowercased()
        if value.contains("java") && (value.contains("example") || value.contains("code")) { return "public record Skill(String name, int level) {}\n\nvar skills = List.of(new Skill(\"Java\", 9), new Skill(\"AI\", 8));\nskills.stream().forEach(System.out::println);" }
        if value.contains("python") && (value.contains("example") || value.contains("code")) { return "skills = [\"Java\", \"Python\", \"Angular\", \"AI\"]\nstrong = [skill for skill in skills if len(skill) >= 4]\nprint(\", \".join(strong))" }
        if value.contains("skyler") || value.contains("one record") { return "Skyler is a ONE Record trust engine that harmonizes dangerous-goods compliance and shipment-level JSON-LD for ground-handler checks." }
        if value.contains("experience") || value.contains("champ") { return "Rey is a Software Engineer at CHAMP Cargosystems. His work spans Angular, Java, Spring, APIs, OAuth, search, caching, Oracle, reusable components, and enterprise air-cargo systems." }
        if value.contains("project") { return "Selected work includes Skyler, a deep-learning Gesture Cursor, rotational churn prediction, and extractive/abstractive text summarization." }
        if value.contains("skill") || value.contains("technology") { return "Core skills include Java, Spring, Angular, TypeScript, Python, C++, AI/ML, NLP, computer vision, Oracle, APIs, and OAuth." }
        if value.contains("portfolio") || value.contains("native") { return "This is the separate native SwiftUI edition of Portfolio OS. Its apps, themes, terminal, assistant, designer, and data stores run directly on iOS without loading the web site." }
        return "I’m strongest on Rey’s experience, projects, skills, Portfolio OS, and concise Java or Python examples. Everything here is generated from an embedded offline knowledge base."
    }
}
