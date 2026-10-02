import Foundation

enum WidgetMode: String, Codable, CaseIterable, Identifiable {
    case native, html
    var id: String { rawValue }
    var label: String { self == .native ? "Native" : "HTML" }
}

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var width: Double { self == .small ? 170 : 364 }
    var height: Double { self == .large ? 382 : 170 }
}

struct NativeDesign: Codable, Equatable {
    enum Layout: String, Codable, CaseIterable { case metric, clock, list, progress }
    var layout: Layout = .metric
    var title = "MY WIDGET"
    var value = "Hello, Rey."
    var subtitle = "Make space for what matters."
    var footer = "Made with ReyWidgets"
    var symbol = "sparkles"
    var background = "#12192C"
    var accent = "#B4FF76"
    var foreground = "#FFFFFF"
    var progress: Double = 0.72
    var rows: [String] = ["Build something useful", "Play a little piano", "Keep learning"]
}

struct APIConfiguration: Codable, Equatable {
    var enabled = false
    var url = ""
    var method = "GET"
    var body = ""
    // Headers (including API keys) live in the shared Keychain, never in this file.
    var credentialID: String = UUID().uuidString
    var refreshMinutes = 30
    var signature: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self).base64EncodedString()) ?? ""
    }
    func validatedURL() throws -> URL {
        guard let value = URL(string: url), value.scheme?.lowercased() == "https",
              value.host != nil, value.user == nil, value.password == nil else {
            throw StudioError.message("Enter an HTTPS API URL without embedded credentials.")
        }
        guard ["GET", "POST"].contains(method) else {
            throw StudioError.message("Choose GET or POST.")
        }
        return value
    }
}

struct WidgetDocument: Codable, Identifiable, Equatable {
    var schemaVersion = 1
    var id = UUID()
    var name = "Untitled widget"
    var mode: WidgetMode = .native
    var native = NativeDesign()
    var html = "<main><h1>Hello, Rey.</h1><p>Your space. Your rules.</p></main>"
    var css = "body { margin:0; background:#12192c; color:white; font-family:system-ui; } main { padding:24px; } h1 { color:#b4ff76; font-size:28px; }"
    var javascript = "// API response: widget.data\n// DOM is ready when this script runs.\n"
    var api = APIConfiguration()
    var sampleJSON = "{\"message\":\"Make something yours.\"}"
    var snapshotRevision: UUID?
    var publishedAt: Date?
    var updatedAt = Date()

    func validate() throws {
        guard schemaVersion == 1 else { throw StudioError.message("This project version is not supported.") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else {
            throw StudioError.message("Give your widget a name of 1–80 characters.")
        }
        guard html.utf8.count + css.utf8.count + javascript.utf8.count <= 200_000 else {
            throw StudioError.message("Keep widget code below 200 KB.")
        }
        guard sampleJSON.utf8.count <= 1_000_000,
              let data = sampleJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil else {
            throw StudioError.message("Sample data must be valid JSON below 1 MB.")
        }
        guard native.rows.count <= 30, native.rows.allSatisfy({ $0.count <= 500 }),
              native.progress.isFinite, (0...1).contains(native.progress), native.symbol.count <= 100,
              native.title.count <= 500, native.value.count <= 500,
              native.subtitle.count <= 1000, native.footer.count <= 500,
              [native.background, native.accent, native.foreground].allSatisfy(Self.isHexColor) else {
            throw StudioError.message("Check the native design: use #RRGGBB colors, short text, and at most 30 rows.")
        }
        if api.enabled { _ = try api.validatedURL() }
        guard (15...1440).contains(api.refreshMinutes), api.body.utf8.count <= 100_000 else {
            throw StudioError.message("Refresh must be 15–1440 minutes; request body must be below 100 KB.")
        }
    }

    static func isHexColor(_ text: String) -> Bool {
        text.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }

    func exportData() throws -> Data {
        var copy = self
        copy.api.credentialID = UUID().uuidString
        copy.snapshotRevision = nil; copy.publishedAt = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(copy)
    }

    static func imported(_ data: Data) throws -> WidgetDocument {
        guard data.count <= 1_500_000 else { throw StudioError.message("Project exceeds 1.5 MB.") }
        var doc = try JSONDecoder().decode(Self.self, from: data)
        try doc.validate()
        doc.id = UUID(); doc.api.credentialID = UUID().uuidString
        doc.snapshotRevision = nil; doc.publishedAt = nil
        // Imported requests are reviewed before they are enabled on this device.
        doc.api.enabled = false
        doc.updatedAt = Date()
        return doc
    }
}

struct APICache: Codable {
    var signature: String
    var json: Data
    var fetchedAt: Date
}

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

enum Bindings {
    // RFC 6901 JSON Pointer. Use {{/current/temperature_2m}} or {{/items/0/name}}.
    static func value(at pointer: String, in data: Data) -> String? {
        guard var node = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return nil }
        if !pointer.isEmpty {
            guard pointer.hasPrefix("/") else { return nil }
            for part in pointer.dropFirst().components(separatedBy: "/") {
                let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
                if let dict = node as? [String: Any], let next = dict[key] { node = next }
                else if let array = node as? [Any], let index = Int(key), index >= 0, index < array.count { node = array[index] }
                else { return nil }
            }
        }
        if node is NSNull { return nil }
        if let string = node as? String { return string }
        if let number = node as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        guard let bytes = try? JSONSerialization.data(withJSONObject: node, options: [.sortedKeys, .fragmentsAllowed]) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    static func render(_ template: String, data: Data) -> String {
        guard let pattern = try? NSRegularExpression(pattern: #"\{\{([^{}]*)\}\}"#) else { return template }
        let source = template as NSString
        var result = template
        for match in pattern.matches(in: template, range: NSRange(location: 0, length: source.length)).reversed() {
            let pointer = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: value(at: pointer, in: data) ?? "—")
            }
        }
        return result
    }
}

import CoreFoundation
