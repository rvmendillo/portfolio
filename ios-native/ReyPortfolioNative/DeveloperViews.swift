import SwiftUI

private struct TerminalLine: Identifiable { let id = UUID(); let text: String; let command: Bool }

struct NativeTerminalView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var command = ""
    @State private var language = "Python"
    @State private var code = "print(\"Hello from native SwiftUI\")\nprint(6 * 7)"
    @State private var codeOutput = "Ready."
    @State private var running = false
    @State private var lines = [TerminalLine(text: "Rey Portfolio Native [Version 2.0]", command: false), TerminalLine(text: "Local terminal. Type 'help' for commands.", command: false)]
    let languages = ["Python", "JavaScript", "Java", "C++"]
    var body: some View {
        VStack(spacing: 10) {
            Picker("Language", selection: $language) { ForEach(languages, id: \.self) { Text($0) } }.pickerStyle(.segmented).padding(.horizontal, 12)
            ScrollViewReader { proxy in ScrollView { LazyVStack(alignment: .leading, spacing: 6) { ForEach(lines) { line in Text(line.text).font(.system(.caption, design: .monospaced)).foregroundStyle(line.command ? .cyan : .white.opacity(0.82)).frame(maxWidth: .infinity, alignment: .leading).id(line.id) } }.padding(13) }.background(Color(hex: "050B14")).clipShape(RoundedRectangle(cornerRadius: 14)).onChange(of: lines.count) { _ in if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) } } }
            HStack { Text("PS native>").font(.caption.monospaced()).foregroundStyle(.cyan); TextField("command", text: $command).textInputAutocapitalization(.never).autocorrectionDisabled().font(.caption.monospaced()).onSubmit(runCommand); Button(action: runCommand) { Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(theme.accent) } }.padding(10).background(Color(hex: "07111E"), in: RoundedRectangle(cornerRadius: 13))
            DisclosureGroup("Python runtime") { VStack(spacing: 8) { TextEditor(text: $code).font(.system(.caption, design: .monospaced)).frame(minHeight: 110).scrollContentBackground(.hidden).padding(7).background(Color(hex: "07111E"), in: RoundedRectangle(cornerRadius: 10)); HStack { Button("Run locally", systemImage: "play.fill") { runCode() }.buttonStyle(.borderedProminent).tint(theme.accent).disabled(running); Button("Stop"){PythonRuntime.shared.stop()}.disabled(!running); Spacer() }; Text(codeOutput).font(.system(.caption2, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(9).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9)) } }.font(.subheadline.bold())
        }.padding(13)
    }
    private func runCode() {
        guard !running else { return }
        guard language == "Python" else { codeOutput = "Export this source to its native compiler. Python runs on this device."; return }
        running = true; codeOutput = "Running Python…"
        Task { do { let result = try await PythonRuntime.shared.run(code); codeOutput = result.output + "\nExit code: \(result.exitCode)" } catch { codeOutput = error.localizedDescription }; running = false }
    }
    private func runCommand() { let clean = String(command.prefix(1_000)); guard !clean.trimmingCharacters(in: .whitespaces).isEmpty else { return }; lines.append(TerminalLine(text: "PS native> \(clean)", command: true)); let result = NativeCommandEngine.execute(clean, theme: theme); if result == "__CLEAR__" { lines.removeAll() } else { lines.append(TerminalLine(text: result, command: false)) }; command = "" }
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
    private func compile() {
        let snapshot = source, inputKind = input, targetKind = target
        output = "Compiling…"
        Task {
            do {
                let generated: String
                if inputKind == "GUI YAML" { generated = NativeTranspiler.compile(source: snapshot, input: inputKind, target: targetKind, customPrint: customPrint) }
                else {
                    guard ["Java", "C++", "Python"].contains(targetKind) else { throw DeveloperError.message("Select GUI YAML for GUI framework exports.") }
                    let python = inputKind == "Python" ? snapshot : NativeTranspiler.humanToPython(snapshot, filipino: inputKind.contains("FIL"), customPrint: customPrint)
                    generated = try await PythonRuntime.shared.compile(python, target: targetKind == "C++" ? "cpp" : targetKind.lowercased())
                }
                if source == snapshot && input == inputKind && target == targetKind { output = generated }
            } catch { if source == snapshot && input == inputKind && target == targetKind { output = error.localizedDescription } }
        }
    }
}

