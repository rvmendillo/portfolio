import SwiftUI
import UniformTypeIdentifiers

enum BuilderComponentKind: String, Codable, CaseIterable, Identifiable {
    case text = "Text"
    case button = "Button"
    case input = "Input"
    case image = "Image"
    case spacer = "Spacer"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .text: return "textformat"
        case .button: return "capsule"
        case .input: return "character.cursor.ibeam"
        case .image: return "photo"
        case .spacer: return "arrow.up.and.down"
        }
    }
}

struct BuilderComponent: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: BuilderComponentKind
    var text: String

    static func make(_ kind: BuilderComponentKind) -> BuilderComponent {
        switch kind {
        case .text: return .init(kind: .text, text: "Hello, world!")
        case .button: return .init(kind: .button, text: "Continue")
        case .input: return .init(kind: .input, text: "Enter text")
        case .image: return .init(kind: .image, text: "photo")
        case .spacer: return .init(kind: .spacer, text: "")
        }
    }
}

struct BuilderProject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var bundleIdentifier: String
    var components: [BuilderComponent] = [
        .make(.text),
        .make(.input),
        .make(.button)
    ]
}

@MainActor
final class BuilderStore: ObservableObject {
    @Published var projects: [BuilderProject] = []
    @Published var selectedID: UUID?

    private let key = "ipa-builder.projects.v1"

    init() {
        load()
        if projects.isEmpty {
            let project = BuilderProject(name: "My App", bundleIdentifier: "com.example.myapp")
            projects = [project]
            selectedID = project.id
            save()
        } else if selectedID == nil {
            selectedID = projects.first?.id
        }
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return projects.firstIndex { $0.id == selectedID }
    }

    var selected: BuilderProject? {
        guard let i = selectedIndex else { return nil }
        return projects[i]
    }

    func create(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = clean.isEmpty ? "Untitled App" : clean
        let slug = title.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        let project = BuilderProject(name: title, bundleIdentifier: "com.example.\(slug.isEmpty ? "app" : slug)")
        projects.append(project)
        selectedID = project.id
        save()
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { projects.indices.contains($0) ? projects[$0].id : nil }
        projects.remove(atOffsets: offsets)
        if let selectedID, ids.contains(selectedID) {
            self.selectedID = projects.first?.id
        }
        save()
    }

    func renameSelected(_ value: String) {
        guard let i = selectedIndex else { return }
        projects[i].name = value
        save()
    }

    func setBundleID(_ value: String) {
        guard let i = selectedIndex else { return }
        projects[i].bundleIdentifier = value
        save()
    }

    func add(_ kind: BuilderComponentKind) {
        guard let i = selectedIndex else { return }
        projects[i].components.append(.make(kind))
        save()
    }

    func moveComponents(from source: IndexSet, to destination: Int) {
        guard let i = selectedIndex else { return }
        projects[i].components.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func deleteComponents(at offsets: IndexSet) {
        guard let i = selectedIndex else { return }
        projects[i].components.remove(atOffsets: offsets)
        save()
    }

    func updateComponent(_ component: BuilderComponent) {
        guard let i = selectedIndex,
              let c = projects[i].components.firstIndex(where: { $0.id == component.id }) else { return }
        projects[i].components[c] = component
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BuilderProject].self, from: data) else { return }
        projects = decoded
    }
}

struct ProjectJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(project: BuilderProject) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.data = (try? encoder.encode(project)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: BuilderStore

    var body: some View {
        TabView {
            NavigationStack { ProjectsView() }
                .tabItem { Label("Projects", systemImage: "square.stack.3d.up") }

            NavigationStack { DesignerView() }
                .tabItem { Label("Designer", systemImage: "rectangle.3.group") }

            NavigationStack { CodePreviewView() }
                .tabItem { Label("Code", systemImage: "chevron.left.forwardslash.chevron.right") }

            NavigationStack { BuildView() }
                .tabItem { Label("Build", systemImage: "hammer") }
        }
    }
}

struct ProjectsView: View {
    @EnvironmentObject private var store: BuilderStore
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        List(selection: $store.selectedID) {
            ForEach(store.projects) { project in
                Button {
                    store.selectedID = project.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: store.selectedID == project.id ? "app.fill" : "app")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(project.name).font(.headline)
                            Text(project.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.selectedID == project.id {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: store.delete)
        }
        .navigationTitle("IPA Builder")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New App", isPresented: $showCreate) {
            TextField("App name", text: $newName)
            Button("Create") { store.create(name: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a native builder project.")
        }
    }
}

struct DesignerView: View {
    @EnvironmentObject private var store: BuilderStore

    var body: some View {
        Group {
            if let project = store.selected {
                List {
                    Section("App") {
                        TextField("Name", text: Binding(
                            get: { store.selected?.name ?? "" },
                            set: { store.renameSelected($0) }
                        ))
                        TextField("Bundle identifier", text: Binding(
                            get: { store.selected?.bundleIdentifier ?? "" },
                            set: { store.setBundleID($0) }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }

                    Section("Canvas") {
                        ForEach(project.components) { component in
                            NavigationLink {
                                ComponentInspector(component: component)
                            } label: {
                                ComponentPreview(component: component)
                            }
                        }
                        .onMove(perform: store.moveComponents)
                        .onDelete(perform: store.deleteComponents)
                    }
                }
                .navigationTitle(project.name)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        EditButton()
                        Menu {
                            ForEach(BuilderComponentKind.allCases) { kind in
                                Button {
                                    store.add(kind)
                                } label: {
                                    Label(kind.rawValue, systemImage: kind.icon)
                                }
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Project", systemImage: "app.dashed", description: Text("Create or select a project first."))
            }
        }
    }
}

struct ComponentPreview: View {
    let component: BuilderComponent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: component.kind.icon)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(component.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                switch component.kind {
                case .text:
                    Text(component.text)
                case .button:
                    Text(component.text)
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                case .input:
                    Text(component.text)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                case .image:
                    Label(component.text, systemImage: "photo")
                case .spacer:
                    Divider()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ComponentInspector: View {
    @EnvironmentObject private var store: BuilderStore
    @State var component: BuilderComponent

    var body: some View {
        Form {
            LabeledContent("Type", value: component.kind.rawValue)
            if component.kind != .spacer {
                TextField(component.kind == .image ? "SF Symbol name" : "Text", text: $component.text)
            }
            Section("Preview") {
                ComponentPreview(component: component)
            }
        }
        .navigationTitle("Inspector")
        .onChange(of: component) { _, newValue in
            store.updateComponent(newValue)
        }
    }
}

struct CodePreviewView: View {
    @EnvironmentObject private var store: BuilderStore

    var body: some View {
        Group {
            if let project = store.selected {
                ScrollView {
                    Text(generateCode(project))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Generated SwiftUI")
            } else {
                ContentUnavailableView("No Project", systemImage: "chevron.left.forwardslash.chevron.right")
            }
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
            "@main",
            "struct GeneratedApp: App {",
            "    var body: some Scene {",
            "        WindowGroup { ContentView() }",
            "    }",
            "}",
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

struct BuildView: View {
    @EnvironmentObject private var store: BuilderStore
    @State private var exporting = false
    @State private var importingTemplate = false
    @State private var templateName: String?

    var body: some View {
        Form {
            if let project = store.selected {
                Section("Current target") {
                    LabeledContent("App", value: project.name)
                    LabeledContent("Bundle ID", value: project.bundleIdentifier)
                    LabeledContent("Components", value: "\(project.components.count)")
                }

                Section("On-device pipeline") {
                    Button {
                        importingTemplate = true
                    } label: {
                        Label(templateName == nil ? "Import RuntimeShell IPA" : "Template: \(templateName!)", systemImage: "shippingbox")
                    }

                    Button {
                        exporting = true
                    } label: {
                        Label("Export Project JSON", systemImage: "square.and.arrow.up")
                    }

                    Text("The builder uses a reusable runtime-shell IPA for compile-free generated apps. Feather handles signing/install after an IPA is produced.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Builder build") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Minimum iOS", value: "17.0")
                    Text("This IPA Builder app itself is compiled natively with SwiftUI for iPhone/iPad.")
                        .font(.footnote)
                }
            } else {
                Text("Select a project first.")
            }
        }
        .navigationTitle("Build")
        .fileExporter(
            isPresented: $exporting,
            document: store.selected.map(ProjectJSONDocument.init(project:)),
            contentType: .json,
            defaultFilename: store.selected.map { "\($0.name.replacingOccurrences(of: " ", with: "-")).builderproject.json" } ?? "project.json"
        ) { _ in }
        .fileImporter(isPresented: $importingTemplate, allowedContentTypes: [.data, .zip], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result {
                templateName = urls.first?.lastPathComponent
            }
        }
    }
}

@main
struct IPABuilderApp: App {
    @StateObject private var store = BuilderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
