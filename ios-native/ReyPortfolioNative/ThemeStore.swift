import SwiftUI

final class ThemeStore: ObservableObject {
    @Published var selectedTheme: PortfolioTheme { didSet { defaults.set(selectedTheme.rawValue, forKey: "native.theme") } }
    @Published var accentHex: String { didSet { defaults.set(accentHex, forKey: "native.accent") } }
    @Published var motionEnabled: Bool { didSet { defaults.set(motionEnabled, forKey: "native.motion") } }
    @Published var profileName: String { didSet { defaults.set(String(profileName.prefix(40)), forKey: "native.profile") } }
    private let defaults = UserDefaults.standard

    init() {
        selectedTheme = PortfolioTheme(rawValue: defaults.string(forKey: "native.theme") ?? "windows") ?? .windows
        accentHex = defaults.string(forKey: "native.accent") ?? "59A8FF"
        motionEnabled = defaults.object(forKey: "native.motion") as? Bool ?? true
        profileName = defaults.string(forKey: "native.profile") ?? "Rey Victor Mendillo"
    }

    var accent: Color { Color(hex: accentHex) }
    var background: LinearGradient {
        switch selectedTheme {
        case .windows: return LinearGradient(colors: [Color(hex: "061020"), Color(hex: "102A50"), Color(hex: "08152A")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ios: return LinearGradient(colors: [Color(hex: "4B2A7C"), Color(hex: "244D91"), Color(hex: "0E7B86")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .resume: return LinearGradient(colors: [Color(hex: "E8EDF3"), .white], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    var primary: Color { selectedTheme == .resume ? Color(hex: "172033") : .white }
    var secondary: Color { selectedTheme == .resume ? Color(hex: "5D6775") : .white.opacity(0.68) }
    var panel: Material { selectedTheme == .resume ? .ultraThinMaterial : .regularMaterial }

    func reset() {
        selectedTheme = .windows; accentHex = "59A8FF"; motionEnabled = true; profileName = "Rey Victor Mendillo"
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r, g, b: UInt64
        if clean.count == 6 { r = value >> 16; g = value >> 8 & 0xFF; b = value & 0xFF }
        else { r = 89; g = 168; b = 255 }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

final class NativePackageStore: ObservableObject {
    @Published private(set) var packages: [NativePackage] = []
    private let key = "native.installed.packages"
    init() { load() }
    func install(name: String, nodes: [DesignerNode], connections: [DesignerConnection]) {
        guard !nodes.isEmpty else { return }
        let package = NativePackage(name: String(name.prefix(48)), nodes: Array(nodes.prefix(50)), connections: Array(connections.prefix(100)))
        packages.removeAll { $0.name.caseInsensitiveCompare(package.name) == .orderedSame }
        packages.insert(package, at: 0); packages = Array(packages.prefix(24)); save()
    }
    func remove(_ package: NativePackage) { packages.removeAll { $0.id == package.id }; save() }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key), let decoded = try? JSONDecoder().decode([NativePackage].self, from: data) else { return }
        packages = Array(decoded.prefix(24))
    }
    private func save() { if let data = try? JSONEncoder().encode(packages) { UserDefaults.standard.set(data, forKey: key) } }
}
