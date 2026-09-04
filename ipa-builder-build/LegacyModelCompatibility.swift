import Foundation

/// Compatibility types for the older embedded Studio Vibe panel.
/// The primary Vibe Code sheet uses AppleScreenPlanner + Foundation Models directly.
struct VibePatch {
    var components: [StudioComponent]
    var variableUpdates: [String: String] = [:]
    var widget: StudioWidgetConfig?
    var summary: String
}

enum LegacyVibeError: LocalizedError {
    case useFoundationModelsBuilder

    var errorDescription: String? {
        "Use the AI Screen Builder from ReyForge Tools for Apple Foundation Models planning."
    }
}

final class LocalVibeModel: @unchecked Sendable {
    static let shared = LocalVibeModel()
    private init() {}

    var isBundled: Bool { false }

    func propose(prompt: String, project: StudioProject) throws -> String {
        throw LegacyVibeError.useFoundationModelsBuilder
    }
}

enum VibePatchParser {
    static func parse(_ output: String, fallbackPrompt: String, project: StudioProject) -> VibePatch {
        heuristic(prompt: fallbackPrompt, project: project)
    }

    static func heuristic(prompt: String, project: StudioProject) -> VibePatch {
        let p = prompt.lowercased()
        let template: StudioTemplate
        let summary: String

        if p.contains("dashboard") {
            template = .dashboard
            summary = "Native dashboard fallback is ready. For AI-selected layout, use ReyForge Tools → Vibe Code."
        } else if p.contains("login") || p.contains("sign in") || p.contains("signin") {
            template = .login
            summary = "Native login fallback is ready. For AI-selected layout, use ReyForge Tools → Vibe Code."
        } else if p.contains("settings") || p.contains("preferences") {
            template = .settings
            summary = "Native settings fallback is ready. For AI-selected layout, use ReyForge Tools → Vibe Code."
        } else if p.contains("profile") || p.contains("account") {
            template = .profile
            summary = "Native profile fallback is ready. For AI-selected layout, use ReyForge Tools → Vibe Code."
        } else if p.contains("shop") || p.contains("store") || p.contains("commerce") || p.contains("product") {
            template = .commerce
            summary = "Native commerce fallback is ready. For AI-selected layout, use ReyForge Tools → Vibe Code."
        } else {
            var title = StudioComponent.make(.text, x: 195, y: 90)
            title.text = prompt.isEmpty ? "New Screen" : String(prompt.prefix(42))
            title.width = 330
            title.height = 52

            var action = StudioComponent.make(.button, x: 195, y: 170)
            action.text = "Continue"
            action.width = 320
            action.actions = [.init(kind: .showAlert, key: "Action", value: "Built with ReyForge")]

            return VibePatch(
                components: [title, action],
                summary: "Basic native fallback is ready. Use ReyForge Tools → Vibe Code for Apple Intelligence screen planning."
            )
        }

        let generated = template.project(name: project.name)
        return VibePatch(components: generated.components, summary: summary)
    }
}
