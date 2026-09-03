import SwiftUI

@main
struct ReyPortfolioNativeApp: App {
    @StateObject private var theme = ThemeStore()
    @StateObject private var packages = NativePackageStore()

    var body: some Scene {
        WindowGroup {
            NativeRootView()
                .environmentObject(theme)
                .environmentObject(packages)
                .preferredColorScheme(theme.selectedTheme == .resume ? .light : .dark)
        }
    }
}
