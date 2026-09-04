import SwiftUI

// MARK: - Inspector

struct StudioInspector: View {
    @EnvironmentObject private var store: StudioStore
    @State private var newActionKind: StudioActionKind = .showAlert
    @State private var newVariableKey = ""
    @State private var newVariableValue = ""

    var body: some View {
        List {
            projectSection

            if let component = store.selectedComponent {
                componentSection(component)
                positionSection(component)
                styleSection(component)
                logicSection(component)
                deleteSection
            } else {
                Section("Component") {
                    ContentUnavailableView(
                        "Select a component",
                        systemImage: "cursorarrow.click",
                        description: Text("Tap an element on the canvas to edit it.")
                    )
                }
            }

            variablesSection
        }
        .listStyle(.sidebar)
    }

    private var projectSection: some View {
        Section("Project") {
            TextField(
                "App name",
                text: Binding(
                    get: { store.selected?.name ?? "" },
                    set: { value in store.updateProject { $0.name = value } }
                )
            )
            TextField(
                "Bundle identifier",
                text: Binding(
                    get: { store.selected?.bundleIdentifier ?? "" },
                    set: { value in store.updateProject { $0.bundleIdentifier = value } }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
    }

    private func componentSection(_ component: StudioComponent) -> some View {
        Section("Component") {
            LabeledContent("Type", value: component.kind.rawValue)

            if component.kind != .divider && component.kind != .spacer {
                TextField("Text / label", text: stringBinding(\.text))
            }

            let detailKinds: [StudioComponentKind] = [
                .image, .symbol, .label, .link, .navigationLink,
                .webView, .map, .shareLink
            ]
            if detailKinds.contains(component.kind) {
                TextField("Detail / URL / symbol", text: stringBinding(\.detail))
                    .textInputAutocapitalization(.never)
            }
        }
    }

    private func positionSection(_ component: StudioComponent) -> some View {
        Section("Position & Size") {
            inspectorSlider(
                label: "X",
                value: doubleBinding(\.x),
                range: 20...370,
                display: Int(component.x)
            )
            inspectorSlider(
                label: "Y",
                value: doubleBinding(\.y),
                range: 30...820,
                display: Int(component.y)
            )
            inspectorSlider(
                label: "W",
                value: doubleBinding(\.width),
                range: 44...370,
                display: Int(component.width)
            )
            inspectorSlider(
                label: "H",
                value: doubleBinding(\.height),
                range: 28...500,
                display: Int(component.height)
            )
        }
    }

    private func styleSection(_ component: StudioComponent) -> some View {
        Section("Style") {
            inspectorSlider(
                label: "Corner",
                value: doubleBinding(\.cornerRadius),
                range: 0...40,
                display: Int(component.cornerRadius)
            )
            inspectorSlider(
                label: "Font",
                value: doubleBinding(\.fontSize),
                range: 10...44,
                display: Int(component.fontSize)
            )

            HStack {
                Text("Value")
                Slider(value: doubleBinding(\.value), in: 0...1)
                Text("\(Int(component.value * 100))%")
                    .monospacedDigit()
                    .frame(width: 44)
            }
        }
    }

    private func logicSection(_ component: StudioComponent) -> some View {
        Section("Logic") {
            if component.actions.isEmpty {
                Text("No actions yet. Add an event action below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(component.actions) { action in
                ActionEditor(actionID: action.id)
            }

            Picker("New action", selection: $newActionKind) {
                ForEach(StudioActionKind.allCases) { kind in
                    Label(kind.rawValue, systemImage: kind.icon)
                        .tag(kind)
                }
            }

            Button {
                store.addAction(newActionKind)
            } label: {
                Label("Add Logic Action", systemImage: "plus.circle")
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                store.deleteSelectedComponent()
            } label: {
                Label("Delete Component", systemImage: "trash")
            }
        }
    }

    private var variablesSection: some View {
        Section("App Variables") {
            if let variables = store.selected?.variables {
                ForEach(variables.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.caption.monospaced())
                        Spacer()
                        Text(variables[key] ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TextField("Variable name", text: $newVariableKey)
                .textInputAutocapitalization(.never)
            TextField("Initial value", text: $newVariableValue)

            Button {
                let key = newVariableKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                store.updateProject { project in
                    project.variables[key] = newVariableValue
                }
                newVariableKey = ""
                newVariableValue = ""
            } label: {
                Label("Add Variable", systemImage: "curlybraces")
            }
        }
    }

    private func inspectorSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: Int
    ) -> some View {
        HStack {
            Text(label).frame(width: 45, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(display)")
                .monospacedDigit()
                .frame(width: 42)
        }
    }

    private func stringBinding(
        _ keyPath: WritableKeyPath<StudioComponent, String>
    ) -> Binding<String> {
        Binding(
            get: { store.selectedComponent?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var component = store.selectedComponent else { return }
                component[keyPath: keyPath] = value
                store.updateComponent(component)
            }
        )
    }

    private func doubleBinding(
        _ keyPath: WritableKeyPath<StudioComponent, Double>
    ) -> Binding<Double> {
        Binding(
            get: { store.selectedComponent?[keyPath: keyPath] ?? 0 },
            set: { value in
                guard var component = store.selectedComponent else { return }
                component[keyPath: keyPath] = value
                store.updateComponent(component)
            }
        )
    }
}

private struct ActionEditor: View {
    @EnvironmentObject private var store: StudioStore
    let actionID: UUID

    private var action: StudioAction? {
        store.selectedComponent?.actions.first { $0.id == actionID }
    }

    var body: some View {
        if let action {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(action.kind.rawValue, systemImage: action.kind.icon)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteAction(actionID)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                }

                Picker("Action", selection: kindBinding) {
                    ForEach(StudioActionKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .labelsHidden()

                TextField("Key / alert title", text: keyBinding)
                TextField("Value / destination / URL", text: valueBinding)
            }
            .padding(.vertical, 4)
        }
    }

    private var kindBinding: Binding<StudioActionKind> {
        Binding(
            get: { action?.kind ?? .showAlert },
            set: { value in update { $0.kind = value } }
        )
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { action?.key ?? "" },
            set: { value in update { $0.key = value } }
        )
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: { action?.value ?? "" },
            set: { value in update { $0.value = value } }
        )
    }

    private func update(_ change: (inout StudioAction) -> Void) {
        guard var current = action else { return }
        change(&current)
        store.updateAction(current)
    }
}

// MARK: - Bottom dock

struct StudioBottomPanel: View {
    let panel: StudioPanel

    var body: some View {
        switch panel {
        case .vibe:
            VibeCodingPanel()
        case .code:
            StudioCodePanel()
        case .build:
            StudioBuildPanel()
        case .widget:
            WidgetExportPanel()
        case .library:
            ComponentLibraryPanel()
        case .templates:
            TemplatePanel()
        }
    }
}

// MARK: - Local vibe coding

struct VibeCodingPanel: View {
    @EnvironmentObject private var store: StudioStore

    @State private var prompt = ""
    @State private var rawOutput = ""
    @State private var pendingPatch: VibePatch?
    @State private var isGenerating = false
    @State private var message = "Describe a feature. SmolLM2 runs locally on this device."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.indigo.gradient)
                        Image(systemName: "sparkles")
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("ReyForge Vibe")
                            .font(.headline)
                        Text(
                            LocalVibeModel.shared.isBundled
                                ? "SmolLM2-360M • local • no API key"
                                : "Local model resource missing"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                    if isGenerating { ProgressView() }
                }

                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 86, maxHeight: 130)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.quaternary)
                    }
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text(
                                "Example: Add a settings screen with notification and Face ID toggles, " +
                                "a Save button, and a medium Home Screen widget."
                            )
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .allowsHitTesting(false)
                        }
                    }

                HStack(alignment: .center) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if pendingPatch != nil {
                        Button("Apply Changes") {
                            applyPatch()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        generate()
                    } label: {
                        Label(
                            isGenerating ? "Thinking…" : "Vibe Build",
                            systemImage: "wand.and.stars"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isGenerating ||
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if !rawOutput.isEmpty {
                    DisclosureGroup("Local model patch") {
                        Text(rawOutput)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(12)
        }
        .background(.background)
    }

    private func generate() {
        guard let project = store.selected else { return }
        let request = prompt
        isGenerating = true
        message = "Running SmolLM2 locally…"
        pendingPatch = nil
        rawOutput = ""

        Task {
            let result: Result<String, Error> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let output = try LocalVibeModel.shared.propose(
                            prompt: request,
                            project: project
                        )
                        continuation.resume(returning: .success(output))
                    } catch {
                        continuation.resume(returning: .failure(error))
                    }
                }
            }

            switch result {
            case .success(let output):
                rawOutput = output
                let patch = VibePatchParser.parse(
                    output,
                    fallbackPrompt: request,
                    project: project
                )
                pendingPatch = patch
                message = patch.summary

            case .failure(let error):
                let patch = VibePatchParser.heuristic(
                    prompt: request,
                    project: project
                )
                rawOutput = "Local model error: \(error.localizedDescription)\n" +
                    "A deterministic offline fallback is ready."
                pendingPatch = patch
                message = "SmolLM2 fallback is ready to apply."
            }

            isGenerating = false
        }
    }

    private func applyPatch() {
        guard let patch = pendingPatch else { return }
        store.updateProject { project in
            project.components.append(contentsOf: patch.components)
            for (key, value) in patch.variableUpdates {
                project.variables[key] = value
            }
            if let widget = patch.widget {
                project.widget = widget
            }
        }
        store.selectedComponentID = patch.components.last?.id ?? store.selectedComponentID
        pendingPatch = nil
        message = "Applied. The generated elements remain draggable and editable."
    }
}

// MARK: - Widget export

struct WidgetExportPanel: View {
    @EnvironmentObject private var store: StudioStore

    var body: some View {
        Form {
            if let project = store.selected {
                Section("WidgetKit") {
                    Toggle(
                        "Include Home Screen Widget",
                        isOn: Binding(
                            get: { store.selected?.widget.enabled ?? false },
                            set: { enabled in
                                store.updateProject { $0.widget.enabled = enabled }
                            }
                        )
                    )

                    TextField("Display name", text: widgetBinding(\.displayName))
                    TextField("Title", text: widgetBinding(\.title))
                    TextField("Subtitle", text: widgetBinding(\.subtitle))
                    TextField("SF Symbol", text: widgetBinding(\.symbol))

                    Picker("Family", selection: widgetBinding(\.family)) {
                        Text("Small").tag("systemSmall")
                        Text("Medium").tag("systemMedium")
                        Text("Large").tag("systemLarge")
                    }

                    TextField("Deep link", text: widgetBinding(\.deepLink))
                        .textInputAutocapitalization(.never)
                }

                Section("Preview") {
                    HStack(spacing: 12) {
                        Image(systemName: project.widget.symbol)
                            .font(.title)
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading) {
                            Text(project.widget.title).font(.headline)
                            Text(project.widget.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(
                        .quaternary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                }

                Section {
                    Text(
                        "When enabled, the GitHub macOS build creates and embeds a real WidgetKit " +
                        "extension in the generated IPA. Launch the installed app once, then add its " +
                        "widget from the iOS Home Screen widget gallery."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func widgetBinding(
        _ keyPath: WritableKeyPath<StudioWidgetConfig, String>
    ) -> Binding<String> {
        Binding(
            get: { store.selected?.widget[keyPath: keyPath] ?? "" },
            set: { value in
                store.updateProject { $0.widget[keyPath: keyPath] = value }
            }
        )
    }
}

// MARK: - Build panel

struct StudioBuildPanel: View {
    @EnvironmentObject private var store: StudioStore
    @EnvironmentObject private var github: GitHubBuildManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Native iOS Build")
                        .font(.headline)
                    Text(github.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if github.isBuilding { ProgressView() }

                Button {
                    guard let project = store.selected else { return }
                    Task { await github.build(project: project) }
                } label: {
                    Label("Build IPA", systemImage: "hammer.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    github.isBuilding ||
                    !github.hasCredential ||
                    store.selected == nil
                )
            }

            if !github.hasCredential {
                Label(
                    "Connect GitHub from the cloud button first.",
                    systemImage: "key"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = github.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let runURL = github.lastRunURL {
                Link("Open GitHub Actions Run", destination: runURL)
            }

            if let ipaURL = github.ipaURL {
                HStack {
                    Label(ipaURL.lastPathComponent, systemImage: "shippingbox.fill")
                    Spacer()
                    ShareLink(item: ipaURL) {
                        Label("Share / Feather", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .background(.background)
    }
}

// MARK: - Code panel

struct StudioCodePanel: View {
    @EnvironmentObject private var store: StudioStore

    var body: some View {
        ScrollView {
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(.background)
    }

    private var code: String {
        guard let project = store.selected else {
            return "// No project selected"
        }

        var lines = [
            "import SwiftUI",
            "",
            "struct ContentView: View {",
            "    var body: some View {",
            "        ZStack {"
        ]

        for component in project.components {
            let text = component.text.replacingOccurrences(of: "\"", with: "\\\"")
            switch component.kind {
            case .text:
                lines.append("            Text(\"\(text)\")")
            case .button:
                lines.append(
                    "            Button(\"\(text)\") { /* \(component.actions.count) action(s) */ }"
                )
            case .textField:
                lines.append(
                    "            TextField(\"\(text)\", text: .constant(\"\"))"
                )
            case .secureField:
                lines.append(
                    "            SecureField(\"\(text)\", text: .constant(\"\"))"
                )
            case .toggle:
                lines.append(
                    "            Toggle(\"\(text)\", isOn: .constant(true))"
                )
            default:
                lines.append(
                    "            // \(component.kind.rawValue): \(text)"
                )
            }
            lines.append(
                "                .frame(width: \(Int(component.width)), height: \(Int(component.height)))"
            )
            lines.append(
                "                .position(x: \(Int(component.x)), y: \(Int(component.y)))"
            )
        }

        lines += [
            "        }",
            "        .frame(width: 390, height: 844)",
            "    }",
            "}"
        ]

        if project.widget.enabled {
            lines.append("")
            lines.append("// WidgetKit extension enabled: \(project.widget.displayName)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - GitHub settings

struct ReyForgeGitHubSettings: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var github: GitHubBuildManager
    @State private var showToken = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository") {
                    TextField("Owner", text: $github.owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Repository", text: $github.repo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Fine-grained token") {
                    if showToken {
                        TextField("github_pat_…", text: $github.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("github_pat_…", text: $github.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Toggle("Show token", isOn: $showToken)
                    Button("Save to iOS Keychain") {
                        github.saveCredential()
                    }
                }

                Section("Permissions") {
                    Label("Contents: Read and write", systemImage: "doc.badge.gearshape")
                    Label("Actions: Read", systemImage: "play.square.stack")
                    Text(
                        "The token stays in this device's Keychain. ReyForge uploads declarative " +
                        "project JSON; GitHub generates and returns the IPA."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if github.hasCredential {
                    Section {
                        Button("Disconnect", role: .destructive) {
                            github.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("ReyForge Cloud Build")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
