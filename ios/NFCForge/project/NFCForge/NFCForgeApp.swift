import SwiftUI

@main
struct NFCForgeApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var nfc = NFCService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(nfc)
                .preferredColorScheme(store.forceDarkMode ? .dark : nil)
                .onAppear { nfc.store = store }
        }
    }
}
