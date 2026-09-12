import SwiftUI
import WidgetKit

@MainActor final class StudioModel: ObservableObject {
    @Published var documents: [WidgetDocument] = []
    @Published var error: String?
    @Published var storageReady = false
    private(set) var store: SharedStore?

    init() { open() }
    func open() {
        do {
            let store = try SharedStore(); self.store = store
            if !UserDefaults.standard.bool(forKey: "didSeedV1") {
                if try store.list().isEmpty {
                    for document in Templates.all { try store.save(document) }
                }
                UserDefaults.standard.set(true, forKey: "didSeedV1")
            }
            documents = try store.list(); storageReady = true
        } catch { self.error = error.localizedDescription; storageReady = false }
    }
    func save(_ input: WidgetDocument) throws {
        guard let store else { throw StudioError.message("Shared widget storage is unavailable.") }
        let previousCredential = (try? store.load(input.id))?.api.credentialID
        var document = input; document.updatedAt = Date()
        try store.save(document); documents = try store.list()
        if let previousCredential, previousCredential != document.api.credentialID { HeaderVault.delete(previousCredential) }
        WidgetCenter.shared.reloadTimelines(ofKind: "ReyWidgets")
    }
    func remove(_ document: WidgetDocument) {
        do {
            guard let store else { return }
            try store.delete(document.id)
            HeaderVault.delete(document.api.credentialID)
            documents = try store.list()
            WidgetCenter.shared.reloadTimelines(ofKind: "ReyWidgets")
        } catch { self.error = error.localizedDescription }
    }
    func duplicate(_ document: WidgetDocument) {
        do {
            var copy = try WidgetDocument.imported(document.exportData())
            copy.name = String((document.name + " copy").prefix(80))
            try save(copy)
        } catch { self.error = error.localizedDescription }
    }
    func importProject(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_500_000 else { throw StudioError.message("Project exceeds 1.5 MB.") }
            try save(WidgetDocument.imported(Data(contentsOf: url)))
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor final class EditorModel: ObservableObject {
    @Published var document: WidgetDocument
    @Published var nativeCode: String
    @Published var previewDocument: WidgetDocument
    @Published var previewData: Data
    @Published var busy = false
    @Published var message: String?
    @Published var error: String?
    @Published var apiResult = "No API request yet."
    @Published var prompt = "A calm, minimal widget with a large greeting and a tiny motivational line. Sage green and cream."
    @Published var generated: GeneratedWidget?
    @Published var rawHeaders = "{}"
    @Published var headersLoaded = false
    private var loadedHeaders = "{}"
    private var task: Task<Void, Never>?

    init(_ document: WidgetDocument) {
        self.document = document; previewDocument = document
        previewData = Data(document.sampleJSON.utf8)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        nativeCode = (try? String(data: encoder.encode(document.native), encoding: .utf8)) ?? "{}"
    }
    func syncCodeFromDesign() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        nativeCode = (try? String(data: encoder.encode(document.native), encoding: .utf8)) ?? nativeCode
    }
    func applyNativeCode() {
        do {
            let design = try JSONDecoder().decode(NativeDesign.self, from: Data(nativeCode.utf8))
            var copy = document; copy.native = design; try copy.validate()
            document.native = design; runPreview(live: false, store: nil)
            message = "Native design applied."
        } catch { self.error = error.localizedDescription }
    }
    func loadHeaders() {
        guard !headersLoaded else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            rawHeaders = String(decoding: try encoder.encode(HeaderVault.read(document.api.credentialID)), as: UTF8.self)
            loadedHeaders = rawHeaders; headersLoaded = true
        } catch { self.error = error.localizedDescription }
    }
    private func persistHeaders() throws {
        guard headersLoaded, rawHeaders != loadedHeaders else { return }
        let headers = try JSONDecoder().decode([String: String].self, from: Data(rawHeaders.utf8))
        // New key identity also invalidates caches when credentials change.
        let newID = UUID().uuidString
        try HeaderVault.save(headers, id: newID)
        document.api.credentialID = newID
        loadedHeaders = rawHeaders
    }
    func runPreview(live: Bool, store: SharedStore?) {
        do {
            try document.validate()
            if live {
                guard let cache = store?.cache(document) else { throw StudioError.message("Test the API first to create a matching response cache.") }
                previewData = cache.json; message = "Preview uses the cached API response."
            } else { previewData = Data(document.sampleJSON.utf8); message = "Preview uses sample data." }
            previewDocument = document
        } catch { self.error = error.localizedDescription }
    }
    func save(studio: StudioModel) {
        do {
            try document.validate(); try persistHeaders(); try studio.save(document)
            message = "Saved. HTML changes need Publish to update the Home Screen."
        } catch { self.error = error.localizedDescription }
    }
    func testAPI(store: SharedStore?) {
        start {
            try self.persistHeaders()
            let json = try await APIClient.fetch(self.document)
            try store?.saveCache(APICache(signature: self.document.api.signature, json: json, fetchedAt: Date()), id: self.document.id)
            let object = try JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed)
            let formatted = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
            self.apiResult = String(decoding: formatted, as: UTF8.self)
            self.previewData = json; self.previewDocument = self.document
            self.message = "API connected. Preview now uses this response."
        }
    }
    func publish(studio: StudioModel) {
        start {
            guard let store = studio.store else { throw StudioError.message("Shared widget storage is unavailable.") }
            try self.document.validate(); try self.persistHeaders()
            var copy = self.document
            let data: Data
            if copy.api.enabled {
                data = try await APIClient.fetch(copy)
                try store.saveCache(APICache(signature: copy.api.signature, json: data, fetchedAt: Date()), id: copy.id)
            } else { data = Data(copy.sampleJSON.utf8) }
            if copy.mode == .html {
                let revision = UUID()
                do {
                    for size in WidgetSize.allCases {
                        try Task.checkCancellation()
                        let renderer = SnapshotRenderer()
                        let png = try await renderer.render(page: HTMLRuntime.page(copy, data: data, size: size), size: size)
                        try png.write(to: store.snapshotURL(copy.id, revision: revision, size: size), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                    copy.snapshotRevision = revision
                } catch {
                    for size in WidgetSize.allCases { try? FileManager.default.removeItem(at: store.snapshotURL(copy.id, revision: revision, size: size)) }
                    throw error
                }
            }
            copy.publishedAt = Date()
            try studio.save(copy)
            store.pruneSnapshots(copy.id, keeping: copy.snapshotRevision)
            self.document = copy; self.previewDocument = copy; self.previewData = data
            self.message = "Published. Add ReyWidgets from the Home Screen widget gallery, then choose this design."
        }
    }
    func generate(engine: AIEngine, modelURL: URL?, useGPU: Bool) {
        start {
            self.generated = try await LocalAI.generate(prompt: self.prompt, engine: engine, modelURL: modelURL, useGPU: useGPU)
            self.message = "AI draft ready. Review the code, then apply it to the editor."
        }
    }
    func applyGenerated() {
        guard let generated else { return }
        document.html = generated.html; document.css = generated.css; document.javascript = generated.javascript
        document.mode = .html; self.generated = nil
        runPreview(live: false, store: nil)
    }
    func cancel() { task?.cancel() }
    private func start(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = nil; error = nil
        task = Task {
            defer { self.busy = false; self.task = nil }
            do { try await operation() }
            catch is CancellationError { self.message = "Cancelled." }
            catch { self.error = error.localizedDescription }
        }
    }
}
