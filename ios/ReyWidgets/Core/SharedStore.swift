import Foundation

struct SharedStore {
    let root: URL
    init(root: URL? = nil) throws {
        if let root { self.root = root }
        else {
            guard let group = Bundle.main.object(forInfoDictionaryKey: "RWAppGroup") as? String,
                  let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                throw StudioError.message("Shared widget storage is unavailable. Sign the app and widget extension with the same App Group.")
            }
            self.root = url.appendingPathComponent("ReyWidgets", isDirectory: true)
        }
        for name in ["Documents", "Cache", "Snapshots"] {
            try FileManager.default.createDirectory(at: self.root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }
    func documentURL(_ id: UUID) -> URL { root.appendingPathComponent("Documents/\(id.uuidString).json") }
    func cacheURL(_ id: UUID) -> URL { root.appendingPathComponent("Cache/\(id.uuidString).json") }
    func snapshotURL(_ id: UUID, revision: UUID, size: WidgetSize) -> URL {
        root.appendingPathComponent("Snapshots/\(id.uuidString)-\(revision.uuidString)-\(size.rawValue).png")
    }
    func list() throws -> [WidgetDocument] {
        let urls = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Documents"), includingPropertiesForKeys: nil)
        return try urls.filter { $0.pathExtension == "json" }.map { url in
            try JSONDecoder().decode(WidgetDocument.self, from: Data(contentsOf: url))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    func load(_ id: UUID) throws -> WidgetDocument {
        try JSONDecoder().decode(WidgetDocument.self, from: Data(contentsOf: documentURL(id)))
    }
    func save(_ doc: WidgetDocument) throws {
        try doc.validate()
        try JSONEncoder().encode(doc).write(to: documentURL(doc.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: documentURL(id))
        try? FileManager.default.removeItem(at: cacheURL(id))
        pruneSnapshots(id, keeping: nil)
    }
    func cache(_ doc: WidgetDocument) -> APICache? {
        guard let bytes = try? Data(contentsOf: cacheURL(doc.id)),
              let result = try? JSONDecoder().decode(APICache.self, from: bytes),
              result.signature == doc.api.signature else { return nil }
        return result
    }
    func saveCache(_ cache: APICache, id: UUID) throws {
        try JSONEncoder().encode(cache).write(to: cacheURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func pruneSnapshots(_ id: UUID, keeping revision: UUID?) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Snapshots"), includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.lastPathComponent.hasPrefix(id.uuidString + "-") {
            if let revision, url.lastPathComponent.contains(revision.uuidString) { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
