import WidgetKit
import SwiftUI
import AppIntents

struct DesignEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget design")
    static var defaultQuery = DesignQuery()
    var id: String
    var name: String
    var mode: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(mode)") }
}

struct DesignQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DesignEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [DesignEntity] {
        try SharedStore().list().map { DesignEntity(id: $0.id.uuidString, name: $0.name, mode: $0.mode.label) }
    }
    func defaultResult() async -> DesignEntity? { try? await suggestedEntities().first }
}

struct ChooseDesignIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose your widget"
    static var description = IntentDescription("Pick a design saved in ReyWidgets.")
    @Parameter(title: "Design") var design: DesignEntity?
}

struct StudioEntry: TimelineEntry {
    var date: Date
    var document: WidgetDocument?
    var data: Data
    var image: Data?
    var status: String?
}

struct StudioProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StudioEntry {
        StudioEntry(date: Date(), document: WidgetDocument(), data: Data("{}".utf8), status: nil)
    }
    func snapshot(for configuration: ChooseDesignIntent, in context: Context) async -> StudioEntry {
        await entry(configuration: configuration, family: context.family, refresh: false)
    }
    func timeline(for configuration: ChooseDesignIntent, in context: Context) async -> Timeline<StudioEntry> {
        let value = await entry(configuration: configuration, family: context.family, refresh: true)
        if value.document?.mode == .html { return Timeline(entries: [value], policy: .never) }
        let interval = max(15, value.document?.api.refreshMinutes ?? 30)
        if value.document?.native.layout == .clock {
            // Precompute clock changes without issuing a network request for
            // every minute. WidgetKit still controls actual display scheduling.
            let minutes = value.document?.api.enabled == true ? min(interval, 60) : 60
            let nextMinute = Date(timeIntervalSince1970: (floor(value.date.timeIntervalSince1970 / 60) + 1) * 60)
            let entries = [value] + (0..<minutes).map { offset in
                var entry = value
                entry.date = nextMinute.addingTimeInterval(Double(offset) * 60)
                return entry
            }
            return Timeline(entries: entries, policy: .after(nextMinute.addingTimeInterval(Double(minutes) * 60)))
        }
        return Timeline(entries: [value], policy: .after(Date().addingTimeInterval(Double(interval) * 60)))
    }
    private func entry(configuration: ChooseDesignIntent, family: WidgetFamily, refresh: Bool) async -> StudioEntry {
        do {
            let store = try SharedStore()
            let document: WidgetDocument?
            if let selected = configuration.design {
                // Do not silently switch a deleted design to a different widget.
                document = UUID(uuidString: selected.id).flatMap { try? store.load($0) }
            } else { document = try store.list().first }
            guard let document else {
                return StudioEntry(date: Date(), document: nil, data: Data(), status: "Open ReyWidgets and choose a saved design.")
            }
            var data = Data(document.sampleJSON.utf8)
            var status: String? = document.api.url.isEmpty ? nil : "Sample data • API off"
            if document.mode == .native && document.api.enabled {
                var cache = store.cache(document)
                var failed = false
                if refresh && (cache == nil || Date().timeIntervalSince(cache!.fetchedAt) >= Double(document.api.refreshMinutes) * 60) {
                    do {
                        let json = try await APIClient.fetch(document)
                        let updated = APICache(signature: document.api.signature, json: json, fetchedAt: Date())
                        try store.saveCache(updated, id: document.id); cache = updated
                    } catch { failed = true }
                }
                if let cache {
                    data = cache.json
                    status = failed ? "Cached • API refresh failed" : "Updated \(cache.fetchedAt.formatted(date: .omitted, time: .shortened))"
                } else { data = Data("{}".utf8); status = "API unavailable • open ReyWidgets" }
            }
            var image: Data?
            if document.mode == .html, let revision = document.snapshotRevision {
                let size: WidgetSize = family == .systemSmall ? .small : family == .systemLarge ? .large : .medium
                image = try? Data(contentsOf: store.snapshotURL(document.id, revision: revision, size: size))
            }
            return StudioEntry(date: Date(), document: document, data: data, image: image, status: status)
        } catch {
            return StudioEntry(date: Date(), document: nil, data: Data(), status: "Open ReyWidgets to check shared storage.")
        }
    }
}

struct StudioWidgetView: View {
    let entry: StudioEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if let document = entry.document {
                if document.mode == .native {
                    ZStack(alignment: .topTrailing) {
                        NativeWidgetView(design: document.native, data: entry.data, compact: family == .systemSmall, large: family == .systemLarge,
                                         status: entry.status, reserveActionSpace: family != .systemSmall && document.api.enabled,
                                         clockDate: entry.date)
                        if family != .systemSmall && document.api.enabled {
                            Button(intent: RefreshNativeIntent(id: document.id)) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                                    .frame(width: 30, height: 30)
                            }.buttonStyle(.plain).foregroundStyle(Color(hex: document.native.accent))
                                .padding(10).accessibilityLabel("Refresh API data")
                        }
                    }
                } else if let bytes = entry.image, let image = UIImage(data: bytes) {
                    Image(uiImage: image).resizable().scaledToFill().clipped()
                        .accessibilityLabel("\(document.name). HTML snapshot. Tap to open the editor.")
                } else {
                    message("Publish your canvas", detail: "Open this design in ReyWidgets and tap Publish.")
                }
            } else { message("Your space awaits", detail: entry.status ?? "Open ReyWidgets to get started.") }
        }
        .widgetURL(entry.document.map { URL(string: "reywidgets://widget/\($0.id.uuidString)")! } ?? URL(string: "reywidgets://studio"))
        .containerBackground(for: .widget) { Color(hex: entry.document?.native.background ?? "#12192C") }
    }
    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "square.grid.2x2.fill").foregroundStyle(Color(hex: "#B4FF76"))
            Text(title).font(.headline)
            Text(detail).font(.caption).opacity(0.7)
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).foregroundStyle(.white)
    }
}

@main struct ReyWidget: Widget {
    let kind = "ReyWidgets"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ChooseDesignIntent.self, provider: StudioProvider()) { entry in
            StudioWidgetView(entry: entry)
        }
        .configurationDisplayName("ReyWidgets")
        .description("Native widgets and HTML canvases, made by you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
