import SwiftUI

struct ContentView: View {
    var body: some View {
        Studio2View()
    }
}

@main
struct ReyForgeApp: App {
    @StateObject private var studio = StudioStore()
    @StateObject private var github = GitHubBuildManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(studio)
                .environmentObject(github)
        }
    }
}
