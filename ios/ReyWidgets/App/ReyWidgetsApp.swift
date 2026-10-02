import SwiftUI

@main struct ReyWidgetsApp: App {
    @StateObject private var studio = StudioModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(studio)
                .tint(Palette.mint).preferredColorScheme(.dark)
        }
    }
}

enum Palette {
    static let background = Color(hex: "#0C1019")
    static let card = Color(hex: "#171E2C")
    static let mint = Color(hex: "#B4FF76")
    static let muted = Color(hex: "#9AA6BD")
}

struct RootView: View {
    @EnvironmentObject private var studio: StudioModel
    @State private var selection = 0
    @State private var path: [UUID] = []
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack(path: $path) {
                StudioView(path: $path)
                    .navigationDestination(for: UUID.self) { id in
                        if let document = studio.documents.first(where: { $0.id == id }) {
                            EditorView(document: document)
                        } else { ContentUnavailableView("Design unavailable", systemImage: "square.dashed", description: Text("This design may have been deleted.")) }
                    }
            }.tabItem { Label("Studio", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { TemplateGallery() }.tabItem { Label("Discover", systemImage: "sparkles.rectangle.stack") }.tag(1)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .onOpenURL { url in
            guard url.scheme == "reywidgets" else { return }
            selection = 0
            if url.host == "widget", let id = UUID(uuidString: url.lastPathComponent) { path = [id] }
        }
        .alert("ReyWidgets", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
            Button("OK", role: .cancel) { studio.error = nil }
        } message: { Text(studio.error ?? "") }
    }
}
