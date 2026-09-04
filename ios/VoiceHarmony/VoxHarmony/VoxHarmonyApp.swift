import SwiftUI

@main
struct VoxHarmonyApp: App {
    @StateObject private var audio = AudioController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audio)
        }
    }
}
