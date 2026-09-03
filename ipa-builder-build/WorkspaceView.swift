import SwiftUI
import UniformTypeIdentifiers

private enum WorkspaceBottomPanel: String, CaseIterable, Identifiable {
    case code = "Code"
    case build = "Build"
    case output = "Output"
    var id: String { rawValue }
}

struct WorkspaceView: View {
    @EnvironmentObject private var store: BuilderStore
    @EnvironmentObject private var github: GitHubBuildManager

    @State private var selectedComponentID: UUID?
    @State private var bottomPanel: WorkspaceBottomPanel? = .code
    @State private var showingPalette = false
    @State private var showingInspector = false
    @State private var showingGitHubSettings = false

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 900 {
                desktopWorkspace
            } else {
                phoneWorkspace
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var desktopWorkspace: some View {
        VStack(spacing: 0) {
            WorkspaceTopBar(
                bottomPanel: $bottomPanel,
                showingGitHubSettings: $showingGitHubSettings
            )

            HStack(spacing: 0) {
                ComponentPalette()
                    .frame(width: 230)
                    .background(.background)

                Divider()

                VStack(spacing: 0) {
                    DeviceCanvas(selectedComponentID: $selectedComponentID)

                    if let panel = bottomPanel {
                        Divider()
                        WorkspaceBottomDock(panel: panel)
                            .frame(height: 250)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                InspectorSidebar(selectedComponentID: $selectedComponentID)
                    .frame(width: 320)
                    .background(.background)
            }
        }
        .sheet(isPresented: $showingGitHubSettings) {
            GitHubSettingsSheet()
                .environmentObject(github)
        }
    }

    private var phoneWorkspace: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CompactCanvasToolbar(
                    showingPalette: $showingPalette,
                    showingInspector: $showingInspector,
                    bottomPanel: $bottomPanel
                )

                DeviceCanvas(selectedComponentID: $selectedComponentID)
            }
            .navigationTitle(store.selected?.name ?? "IPA Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingGitHubSettings = true
                    } label: {
                        Image(systemName: github.hasCredential ? "icloud.and.arrow.up.fill" : "icloud.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showingPalette) {
            NavigationStack {
                ComponentPalette()
                    .navigationTitle("Components")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingPalette = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingInspector) {
            NavigationStack {
                InspectorSidebar(selectedComponentID: $selectedComponentID)
                    .navigationTitle("Inspector")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingInspector = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $bottomPanel) { panel in
            NavigationStack {
                WorkspaceBottomDock(panel: panel)
                    .navigationTitle(panel.rawValue)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { bottomPanel = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingGitHubSettings) {
            GitHubSettingsSheet()
                .environmentObject(github)
        }
    }
}

private struct WorkspaceTopBar: View {
    @EnvironmentObject private var store: BuilderStore
    @EnvironmentObject private var github: GitHubBuildManager

    @Binding var bottomPanel: WorkspaceBottomPanel?
    @Binding var showingGitHubSettings: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label("IPA Builder", systemImage: "hammer.fill")
                .font(.headline)

            Divider().frame(height: 22)

            Menu {
                ForEach(store.projects) { project in
                    Button {
                        store.selectedID = project.id
                    } label: {
                        if store.selectedID == project.id {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(store.selected?.name ?? "Select Project")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }

            Spacer()

            Picker("Bottom Panel", selection: Binding(
                get: { bottomPanel ?? .code },
                set: { bottomPanel = $0 }
            )) {
                ForEach(WorkspaceBottomPanel.allCases) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Button {
                bottomPanel = bottomPanel == nil ? .code : nil
            } label: {
                Image(systemName: bottomPanel == nil ? "rectangle.bottomhalf.inset.filled" : "rectangle.bottomhalf.inset.filled.badge.minus")
            }

            Button {
                showingGitHubSettings = true
            } label: {
                Label(
                    github.isBuilding ? "Building…" : "GitHub",
                    systemImage: github.hasCredential ? "icloud.and.arrow.up.fill" : "icloud.and.arrow.up"
                )
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.bar)
    }
}

private struct CompactCanvasToolbar: View {
    @Binding var showingPalette: Bool
    @Binding var showingInspector: Bool
    @Binding var bottomPanel: WorkspaceBottomPanel?

    var body: some View {
        HStack {
            Button {
                showingPalette = true
            } label: {
                Label("Widgets", systemImage: "square.grid.2x2")
            }

            Spacer()

            Menu {
                Button("Code") { bottomPanel = .code }
                Button("Build") { bottomPanel = .build }
                Button("Output") { bottomPanel = .output }
            } label: {
                Label("Panels", systemImage: "rectangle.bottomhalf.inset.filled")
            }

            Button {
                showingInspector = true
            } label: {
                Label("Properties", systemImage: "slider.horizontal.3")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.bar)
    }
}

private struct ComponentPalette: View {
    @EnvironmentObject private var store: BuilderStore

    var body: some View {
        List {
            Section("Components") {
                ForEach(BuilderComponentKind.allCases) { kind in
                    Button {
                        store.add(kind)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.icon)
                                .frame(width: 28, height: 28)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.rawValue)
                                    .foregroundStyle(.primary)
                                Text(description(kind))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .onDrag {
                        NSItemProvider(object: kind.rawValue as NSString)
                    }
                }
            }

            Section("Project") {
                Label("Pages", systemImage: "rectangle.on.rectangle")
                Label("Components", systemImage: "shippingbox")
                Label("Assets", systemImage: "photo.on.rectangle")
                Label("Variables", systemImage: "curlybraces")
            }

            Section("Logic") {
                Label("Actions", systemImage: "bolt")
                Label("API Calls", systemImage: "network")
                Label("Local State", systemImage: "internaldrive")
            }
        }
        .listStyle(.sidebar)
    }

    private func description(_ kind: BuilderComponentKind) -> String {
        switch kind {
        case .text: return "Label / heading"
        case .button: return "Tap action"
        case .input: return "Text field"
        case .image: return "Image / symbol"
        case .spacer: return "Flexible spacing"
        }
    }
}

private struct DeviceCanvas: View {
    @EnvironmentObject private var store: BuilderStore
    @Binding var selectedComponentID: UUID?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
                .ignoresSafeArea()

            if let project = store.selected {
                VStack(spacing: 12) {
                    HStack {
                        Text("iPhone Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("390 × 844")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 430)

                    ScrollView {
                        VStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Capsule().frame(width: 60, height: 5)
                            }
                            .padding(.top, 10)

                            VStack(spacing: 14) {
                                if project.components.isEmpty {
                                    ContentUnavailableView(
                                        "Drop components here",
                                        systemImage: "square.and.arrow.down",
                                        description: Text("Drag from the component palette or tap a widget.")
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 500)
                                } else {
                                    ForEach(project.components) { component in
                                        CanvasComponentCard(
                                            component: component,
                                            isSelected: selectedComponentID == component.id
                                        )
                                        .onTapGesture {
                                            selectedComponentID = component.id
                                        }
                                    }
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    .frame(width: 390, height: 700)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 42, style: .continuous)
                            .stroke(.quaternary, lineWidth: 2)
                    }
                    .shadow(radius: 18, y: 8)
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        guard let provider = providers.first else { return false }
                        provider.loadObject(ofClass: NSString.self) { value, _ in
                            guard let raw = value as? String,
                                  let kind = BuilderComponentKind(rawValue: raw) else { return }
                            Task { @MainActor in
                                store.add(kind)
                            }
                        }
                        return true
                    }
                }
                .padding(24)
            } else {
                ContentUnavailableView(
                    "No project selected",
                    systemImage: "app.dashed",
                    description: Text("Choose or create a project to start designing.")
                )
            }
        }
    }
}

private struct CanvasComponentCard: View {
    let component: BuilderComponent
    let isSelected: Bool

    var body: some View {
        Group {
            switch component.kind {
            case .text:
                Text(component.text)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .button:
                Text(component.text)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            case .input:
                HStack {
                    Text(component.text)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            case .image:
                VStack(spacing: 8) {
                    Image(systemName: component.text.isEmpty ? "photo" : component.text)
                        .font(.system(size: 48))
                    Text(component.text.isEmpty ? "Image" : component.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            case .spacer:
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 34)
                    .overlay {
                        Label("Spacer", systemImage: "arrow.up.and.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
    }
}

private struct InspectorSidebar: View {
    @EnvironmentObject private var store: BuilderStore
    @Binding var selectedComponentID: UUID?

    var selectedComponent: BuilderComponent? {
        guard let project = store.selected,
              let id = selectedComponentID else { return nil }
        return project.components.first(where: { $0.id == id })
    }

    var body: some View {
        List {
            Section("Properties") {
                if let component = selectedComponent {
                    LabeledContent("Type", value: component.kind.rawValue)

                    if component.kind != .spacer {
                        TextField(
                            component.kind == .image ? "SF Symbol" : "Text",
                            text: Binding(
                                get: { selectedComponent?.text ?? "" },
                                set: { newValue in
                                    var copy = component
                                    copy.text = newValue
                                    store.updateComponent(copy)
                                }
                            )
                        )
                    }
                } else {
                    Text("Select a component on the canvas.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Layout") {
                LabeledContent("Width", value: "Auto")
                LabeledContent("Height", value: "Auto")
                LabeledContent("Padding", value: "10")
                LabeledContent("Alignment", value: "Center")
            }

            Section("Style") {
                Label("Typography", systemImage: "textformat")
                Label("Fill", systemImage: "paintpalette")
                Label("Border & Radius", systemImage: "square")
                Label("Effects", systemImage: "sparkles")
            }

            Section("Actions") {
                Label("On Tap", systemImage: "hand.tap")
                Label("Navigation", systemImage: "arrow.right")
                Label("Set Variable", systemImage: "curlybraces")
            }
        }
        .listStyle(.sidebar)
    }
}

private struct WorkspaceBottomDock: View {
    @EnvironmentObject private var store: BuilderStore
    @EnvironmentObject private var github: GitHubBuildManager

    let panel: WorkspaceBottomPanel

    var body: some View {
        Group {
            switch panel {
            case .code:
                CodeDock()
            case .build:
                BuildDock()
            case .output:
                OutputDock()
            }
        }
        .background(.background)
    }
}

private struct CodeDock: View {
    @EnvironmentObject private var store: BuilderStore

    var body: some View {
        ScrollView {
            Text(store.selected.map(generateCode) ?? "// No project selected")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func generateCode(_ project: BuilderProject) -> String {
        var lines = [
            "import SwiftUI",
            "",
            "struct ContentView: View {",
            "    @State private var input = \"\"",
            "    var body: some View {",
            "        VStack(spacing: 16) {"
        ]

        for component in project.components {
            switch component.kind {
            case .text:
                lines.append("            Text(\"\(escaped(component.text))\")")
            case .button:
                lines.append("            Button(\"\(escaped(component.text))\") { }")
            case .input:
                lines.append("            TextField(\"\(escaped(component.text))\", text: $input)")
            case .image:
                lines.append("            Image(systemName: \"\(escaped(component.text))\")")
            case .spacer:
                lines.append("            Spacer()")
            }
        }

        lines += [
            "        }",
            "        .padding()",
            "    }",
            "}"
        ]
        return lines.joined(separator: "\n")
    }
}

private struct BuildDock: View {
    @EnvironmentObject private var store: BuilderStore
    @EnvironmentObject private var github: GitHubBuildManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GitHub macOS Build")
                        .font(.headline)
                    Text(github.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if github.isBuilding {
                    ProgressView()
                }

                Button {
                    guard let project = store.selected else { return }
                    Task { await github.build(project: project) }
                } label: {
                    Label("Build IPA", systemImage: "hammer.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(github.isBuilding || !github.hasCredential || store.selected == nil)
            }

            if !github.hasCredential {
                Text("Configure GitHub access first using the cloud button in the toolbar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = github.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
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
        .padding()
    }
}

private struct OutputDock: View {
    @EnvironmentObject private var github: GitHubBuildManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Build Output")
                .font(.headline)
            Text(github.status)
                .font(.system(.caption, design: .monospaced))

            if let runURL = github.lastRunURL {
                Link(destination: runURL) {
                    Label("Open Actions run", systemImage: "arrow.up.right.square")
                }
            }

            if let error = github.lastError {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

private struct GitHubSettingsSheet: View {
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

                Section("GitHub Access") {
                    if showToken {
                        TextField("Fine-grained token", text: $github.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Fine-grained token", text: $github.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Toggle("Show token", isOn: $showToken)

                    Button("Save to iOS Keychain") {
                        github.saveCredential()
                    }
                }

                Section {
                    Text("Use a fine-grained token restricted to this repository with Contents: read/write and Actions: read/write. The token stays in this device's Keychain.")
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
            .navigationTitle("GitHub Build")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
