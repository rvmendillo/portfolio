import AppIntents
import WidgetKit

struct RefreshNativeIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh widget data"
    static var description = IntentDescription("Fetch the configured API for this native widget.")
    static var openAppWhenRun = false
    @Parameter(title: "Widget ID") var widgetID: String
    init() {}
    init(id: UUID) { widgetID = id.uuidString }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: widgetID) else { throw StudioError.message("Invalid widget ID.") }
        let store = try SharedStore()
        let document = try store.load(id)
        if document.mode == .native && document.api.enabled {
            let json = try await APIClient.fetch(document)
            try store.saveCache(APICache(signature: document.api.signature, json: json, fetchedAt: Date()), id: id)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ReyWidgets")
        return .result()
    }
}
