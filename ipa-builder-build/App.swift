import SwiftUI

struct ContentView: View {
    var body: some View {
        ReyForgeRootV21()
    }
}

@main
struct ReyForgeApp: App {
    @StateObject private var studio = StudioStore()
    @StateObject private var github = GitHubBuildManager()
    @StateObject private var signer = BuiltInSigningManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(studio)
                .environmentObject(github)
                .environmentObject(signer)
        }
    }
}
