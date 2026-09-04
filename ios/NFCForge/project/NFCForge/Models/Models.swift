import Foundation
import CoreNFC

struct NDEFRecordModel: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case text = "Text"
        case url = "URL"
        case phone = "Phone"
        case email = "Email"
        case sms = "SMS"
        case location = "Location"
        case contact = "Contact"
        case wifi = "Wi‑Fi"
        case json = "JSON"
        case mime = "Custom MIME"
        case external = "External Type"
        case raw = "Raw"
        var id: String { rawValue }
    }

    var id = UUID()
    var kind: Kind
    var value: String
    var auxiliary: String = ""
    var type: String = ""
    var identifierHex: String = ""
    var payloadHex: String = ""
    var tnfRaw: UInt8 = 0

    static func blank(_ kind: Kind = .text) -> NDEFRecordModel {
        NDEFRecordModel(kind: kind, value: "")
    }
}

struct NFCSnapshot: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var tagType: String
    var identifierHex: String
    var ndefStatus: String
    var capacity: Int
    var records: [NDEFRecordModel]
    var protocolDetails: [String: String] = [:]
}

struct NFCTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var icon: String
    var records: [NDEFRecordModel]

    static let builtIns: [NFCTemplate] = [
        .init(name: "Website", icon: "globe", records: [.init(kind: .url, value: "https://example.com")]),
        .init(name: "Contact card", icon: "person.crop.circle", records: [.init(kind: .contact, value: "BEGIN:VCARD\nVERSION:3.0\nFN:Your Name\nTEL:+63\nEMAIL:you@example.com\nEND:VCARD")]),
        .init(name: "Wi‑Fi note", icon: "wifi", records: [.init(kind: .wifi, value: "MyNetwork", auxiliary: "WPA;password")]),
        .init(name: "Call me", icon: "phone", records: [.init(kind: .phone, value: "+639000000000")]),
        .init(name: "Location", icon: "location", records: [.init(kind: .location, value: "14.5995,120.9842")]),
        .init(name: "JSON payload", icon: "curlybraces", records: [.init(kind: .json, value: "{\n  \"hello\": \"world\"\n}")])
    ]
}

@MainActor
final class AppStore: ObservableObject {
    @Published var history: [NFCSnapshot] = [] { didSet { saveHistory() } }
    @Published var templates: [NFCTemplate] = [] { didSet { saveTemplates() } }
    @Published var draftRecords: [NDEFRecordModel] = [.blank()] { didSet { saveDraft() } }
    @Published var lockAfterWrite = false
    @Published var forceDarkMode = false

    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "history"), let decoded = try? JSONDecoder().decode([NFCSnapshot].self, from: data) { history = decoded }
        if let data = defaults.data(forKey: "templates"), let decoded = try? JSONDecoder().decode([NFCTemplate].self, from: data) { templates = decoded }
        if templates.isEmpty { templates = NFCTemplate.builtIns }
        if let data = defaults.data(forKey: "draft"), let decoded = try? JSONDecoder().decode([NDEFRecordModel].self, from: data), !decoded.isEmpty { draftRecords = decoded }
        lockAfterWrite = defaults.bool(forKey: "lockAfterWrite")
        forceDarkMode = defaults.bool(forKey: "forceDarkMode")
    }

    func addHistory(_ snapshot: NFCSnapshot) {
        history.insert(snapshot, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
    }

    func clearHistory() { history.removeAll() }
    func useTemplate(_ template: NFCTemplate) { draftRecords = template.records }
    func saveCurrentAsTemplate(name: String) { templates.insert(.init(name: name, icon: "square.stack.3d.up", records: draftRecords), at: 0) }

    private func saveHistory() { if let d = try? JSONEncoder().encode(history) { defaults.set(d, forKey: "history") } }
    private func saveTemplates() { if let d = try? JSONEncoder().encode(templates) { defaults.set(d, forKey: "templates") } }
    private func saveDraft() { if let d = try? JSONEncoder().encode(draftRecords) { defaults.set(d, forKey: "draft") } }
    func savePreferences() { defaults.set(lockAfterWrite, forKey: "lockAfterWrite"); defaults.set(forceDarkMode, forKey: "forceDarkMode") }
}
