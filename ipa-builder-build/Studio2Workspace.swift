import SwiftUI

// MARK: - Workspace routing

enum StudioPanel: String, CaseIterable, Identifiable {
    case library = "Library"
    case templates = "Templates"
    case vibe = "Vibe AI"
    case code = "Code"
    case build = "Build"
    case widget = "Widget"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .templates: return "square.stack.3d.up"
        case .vibe: return "sparkles"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .build: return "hammer"
        case .widget: return "square.grid.2x2.fill"
        }
    }
}

struct Studio2View: View {
    @EnvironmentObject private var store: StudioStore
    @EnvironmentObject private var github: GitHubBuildManager

    @State private var leftPanel: StudioPanel = .library
    @State private var bottomPanel: StudioPanel? = .code
    @State private var showInspector = false
    @State private var showLeftPanel = false
    @State private var showGitHub = false
    @State private var showNewProject = false
    @State private var newName = ""
    @State private var newTemplate: StudioTemplate = .blank

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 900 {
                desktopWorkspace
            } else {
                compactWorkspace
            }
        }
        .tint(.indigo)
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showGitHub) {
            ReyForgeGitHubSettings()
                .environmentObject(github)
        }
        .sheet(isPresented: $showNewProject) {
            newProjectSheet
        }
    }

    private var newProjectSheet: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("App name", text: $newName)
                    Picker("Template", selection: $newTemplate) {
                        ForEach(StudioTemplate.allCases) { template in
                            Label(template.rawValue, systemImage: template.icon)
                                .tag(template)
                        }
                    }
                }

                Section {
                    Button("Create Project") {
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.newProject(
                            template: newTemplate,
                            name: trimmed.isEmpty ? nil : trimmed
                        )
                        newName = ""
                        showNewProject = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("New ReyForge App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewProject = false }
                }
            }
        }
    }

    private var desktopWorkspace: some View {
        VStack(spacing: 0) {
            ReyForgeTopBar(
                showGitHub: $showGitHub,
                showNewProject: $showNewProject,
                bottomPanel: $bottomPanel
            )
            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Picker("Tool", selection: $leftPanel) {
                        ForEach([StudioPanel.library, .templates, .vibe]) { panel in
                            Image(systemName: panel.icon).tag(panel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(10)

                    switch leftPanel {
                    case .library:
                        ComponentLibraryPanel()
                    case .templates:
                        TemplatePanel()
                    case .vibe:
                        VibeCodingPanel()
                    default:
                        EmptyView()
                    }
                }
                .frame(width: 270)
                .background(.background)

                Divider()

                VStack(spacing: 0) {
                    ReyForgeCanvas()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let bottomPanel {
                        Divider()
                        StudioBottomPanel(panel: bottomPanel)
                            .frame(height: 280)
                    }
                }

                Divider()

                StudioInspector()
                    .frame(width: 335)
                    .background(.background)
            }
        }
    }

    private var compactWorkspace: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        showLeftPanel = true
                    } label: {
                        Label("Add", systemImage: "plus.square.on.square")
                    }

                    Spacer()

                    Menu {
                        Button {
                            bottomPanel = .vibe
                        } label: {
                            Label("Vibe AI", systemImage: "sparkles")
                        }
                        Button {
                            bottomPanel = .code
                        } label: {
                            Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        Button {
                            bottomPanel = .widget
                        } label: {
                            Label("Widget", systemImage: "square.grid.2x2")
                        }
                        Button {
                            bottomPanel = .build
                        } label: {
                            Label("Build", systemImage: "hammer")
                        }
                    } label: {
                        Label("Tools", systemImage: "wrench.and.screwdriver")
                    }

                    Button {
                        showInspector = true
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(.bar)

                ReyForgeCanvas()
            }
            .navigationTitle(store.selected?.name ?? "ReyForge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showNewProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGitHub = true
                    } label: {
                        Image(
                            systemName: github.hasCredential
                                ? "icloud.and.arrow.up.fill"
                                : "icloud.and.arrow.up"
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showLeftPanel) {
            NavigationStack {
                TabView {
                    ComponentLibraryPanel()
                        .tabItem { Label("Components", systemImage: "square.grid.2x2") }
                    TemplatePanel()
                        .tabItem { Label("Templates", systemImage: "square.stack.3d.up") }
                }
                .navigationTitle("Insert")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showLeftPanel = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showInspector) {
            NavigationStack {
                StudioInspector()
                    .navigationTitle("Inspector")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showInspector = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $bottomPanel) { panel in
            NavigationStack {
                StudioBottomPanel(panel: panel)
                    .navigationTitle(panel.rawValue)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { bottomPanel = nil }
                        }
                    }
            }
            .presentationDetents(panel == .vibe ? [.large] : [.medium, .large])
        }
    }
}

// MARK: - Top bar

private struct ReyForgeTopBar: View {
    @EnvironmentObject private var store: StudioStore
    @EnvironmentObject private var github: GitHubBuildManager

    @Binding var showGitHub: Bool
    @Binding var showNewProject: Bool
    @Binding var bottomPanel: StudioPanel?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.indigo.gradient)
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 0) {
                Text("ReyForge")
                    .font(.headline.weight(.bold))
                Text("Native iOS Studio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 26)

            Menu {
                ForEach(store.projects) { project in
                    Button {
                        store.selectedID = project.id
                        store.selectedComponentID = project.components.first?.id
                    } label: {
                        if store.selectedID == project.id {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }

                Divider()

                Button {
                    showNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }

                Button {
                    store.duplicateCurrent()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(store.selected?.name ?? "Project")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }

            Spacer()

            HStack(spacing: 2) {
                ForEach([StudioPanel.vibe, .code, .widget, .build]) { panel in
                    Button {
                        bottomPanel = bottomPanel == panel ? nil : panel
                    } label: {
                        Label(panel.rawValue, systemImage: panel.icon)
                            .labelStyle(.iconOnly)
                            .frame(width: 34, height: 30)
                    }
                    .background(
                        bottomPanel == panel ? Color.indigo.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                }
            }

            Button {
                showGitHub = true
            } label: {
                Label(
                    github.isBuilding ? "Building" : "GitHub",
                    systemImage: github.hasCredential
                        ? "icloud.and.arrow.up.fill"
                        : "icloud.and.arrow.up"
                )
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(.bar)
    }
}

// MARK: - Component library

struct ComponentLibraryPanel: View {
    @EnvironmentObject private var store: StudioStore
    @State private var search = ""

    private let categories = ["Display", "Inputs", "Actions", "Layout", "Advanced"]

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                let items = StudioComponentKind.allCases.filter {
                    $0.category == category &&
                    (search.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(search))
                }

                if !items.isEmpty {
                    Section(category) {
                        ForEach(items) { kind in
                            Button {
                                store.add(kind)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: kind.icon)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            .indigo.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 7)
                                        )
                                    Text(kind.rawValue)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .draggable(kind.rawValue)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Find a native component")
        .listStyle(.sidebar)
    }
}

// MARK: - Templates

struct TemplatePanel: View {
    @EnvironmentObject private var store: StudioStore

    var body: some View {
        List {
            Section("Full-featured starters") {
                ForEach(StudioTemplate.allCases) { template in
                    Button {
                        store.newProject(template: template)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: template.icon)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(
                                    .indigo.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.rawValue)
                                    .foregroundStyle(.primary)
                                    .font(.subheadline.weight(.semibold))
                                Text(description(for: template))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func description(for template: StudioTemplate) -> String {
        switch template {
        case .blank: return "Minimal editable canvas"
        case .login: return "Auth fields, action and link"
        case .dashboard: return "Gauge, progress, list and actions"
        case .settings: return "Toggles, picker, slider and navigation"
        case .profile: return "Image, profile fields and sharing"
        case .commerce: return "Product UI, quantity and cart action"
        case .componentGallery: return "Nearly the entire ReyForge native control catalog"
        case .widgetStarter: return "App + WidgetKit Home Screen target"
        }
    }
}

// MARK: - Canvas

struct ReyForgeCanvas: View {
    @EnvironmentObject private var store: StudioStore

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(220, geometry.size.width - 28)
            let availableHeight = max(360, geometry.size.height - 28)
            let scale = min(
                1.0,
                max(0.42, min(availableWidth / 390, availableHeight / 844))
            )

            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    HStack {
                        Label("iPhone 390 × 844", systemImage: "iphone")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let component = store.selectedComponent {
                            Text(
                                "x \(Int(component.x))  y \(Int(component.y))  " +
                                "\(Int(component.width))×\(Int(component.height))"
                            )
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 390 * scale)

                    canvasSurface(scale: scale)
                }
                .padding(12)
            }
        }
    }

    private func canvasSurface(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 390, height: 844)

            VStack {
                Capsule()
                    .fill(.primary.opacity(0.82))
                    .frame(width: 104, height: 28)
                    .padding(.top, 8)
                Spacer()
            }
            .frame(width: 390, height: 844)
            .allowsHitTesting(false)

            if let project = store.selected {
                ForEach(project.components) { component in
                    MovableStudioComponent(
                        component: component,
                        isSelected: store.selectedComponentID == component.id,
                        canvasScale: scale
                    )
                }
            }
        }
        .frame(width: 390, height: 844)
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .stroke(.primary.opacity(0.16), lineWidth: 2)
        }
        .shadow(radius: 20, y: 10)
        .dropDestination(for: String.self) { items, location in
            guard let raw = items.first,
                  let kind = StudioComponentKind(rawValue: raw) else {
                return false
            }
            store.add(kind, at: location)
            return true
        }
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 390 * scale, height: 844 * scale, alignment: .topLeading)
    }
}

private struct MovableStudioComponent: View {
    @EnvironmentObject private var store: StudioStore

    let component: StudioComponent
    let isSelected: Bool
    let canvasScale: CGFloat

    @State private var dragOrigin: CGPoint?
    @State private var resizeOrigin: CGSize?

    var body: some View {
        StudioComponentRenderer(component: component)
            .frame(width: component.width, height: component.height)
            .background(isSelected ? Color.indigo.opacity(0.06) : Color.clear)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: max(4, component.cornerRadius))
                        .stroke(
                            .indigo,
                            style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                        )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    resizeHandle
                }
            }
            .position(x: component.x, y: component.y)
            .contentShape(Rectangle())
            .onTapGesture {
                store.selectedComponentID = component.id
            }
            .gesture(moveGesture)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                store.selectedComponentID = component.id
                if dragOrigin == nil {
                    dragOrigin = CGPoint(x: component.x, y: component.y)
                }
                let origin = dragOrigin ?? CGPoint(x: component.x, y: component.y)
                store.moveSelected(
                    to: CGPoint(
                        x: origin.x + value.translation.width / canvasScale,
                        y: origin.y + value.translation.height / canvasScale
                    )
                )
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(.indigo, in: Circle())
            .offset(x: 10, y: 10)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        store.selectedComponentID = component.id
                        if resizeOrigin == nil {
                            resizeOrigin = CGSize(
                                width: component.width,
                                height: component.height
                            )
                        }
                        let origin = resizeOrigin ?? .zero
                        store.resizeSelected(
                            width: origin.width + value.translation.width / canvasScale,
                            height: origin.height + value.translation.height / canvasScale
                        )
                    }
                    .onEnded { _ in
                        resizeOrigin = nil
                    }
            )
    }
}
