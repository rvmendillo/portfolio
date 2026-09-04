import Foundation
import FoundationModels

@Generable
enum PlannedComponentKind {
    case text
    case button
    case textField
    case secureField
    case textEditor
    case image
    case symbol
    case label
    case toggle
    case slider
    case stepper
    case picker
    case datePicker
    case progress
    case gauge
    case divider
    case link
    case menu
    case navigationLink
    case list
    case scrollView
    case vStack
    case hStack
    case zStack
    case form
    case section
    case roundedRectangle
    case circle
    case webView
    case map
    case shareLink
}

@Generable
enum PlannedActionKind {
    case none
    case showAlert
    case navigate
    case setVariable
    case toggleVariable
    case increment
    case decrement
    case openURL
    case saveLocal
    case apiGET
    case copyText
}

@Generable
struct PlannedComponent {
    @Guide(description: "The native SwiftUI component that best matches this UI element.")
    var kind: PlannedComponentKind

    @Guide(description: "Primary visible text, title, placeholder, or SF Symbol name.")
    var text: String

    @Guide(description: "Optional secondary text, URL, destination, symbol, or extra configuration.")
    var detail: String

    @Guide(description: "Horizontal center position on a 390 point wide iPhone canvas.", .range(20...370))
    var x: Int

    @Guide(description: "Vertical center position on an 844 point tall iPhone canvas.", .range(30...810))
    var y: Int

    @Guide(description: "Component width in points.", .range(44...370))
    var width: Int

    @Guide(description: "Component height in points.", .range(28...700))
    var height: Int

    @Guide(description: "The primary interaction this component should perform.")
    var action: PlannedActionKind

    @Guide(description: "Action key, such as alert title, variable name, or navigation label. Empty when no action is needed.")
    var actionKey: String

    @Guide(description: "Action value, such as alert message, URL, destination, or variable value. Empty when no action is needed.")
    var actionValue: String
}

@Generable
struct NativeScreenPlan {
    @Guide(description: "A concise description of the screen the planner created.")
    var summary: String

    @Guide(description: "True when the request asks to create or redesign a whole screen; false when it only asks to add or modify part of the existing screen.")
    var replaceExisting: Bool

    @Guide(description: "Native iOS components needed for the screen, ordered from top to bottom.", .maximumCount(18))
    var components: [PlannedComponent]
}

@MainActor
final class AppleScreenPlanner: ObservableObject {
    static let shared = AppleScreenPlanner()

    private let model = SystemLanguageModel.default

    var isAvailable: Bool { model.isAvailable }

    var availabilityText: String {
        switch model.availability {
        case .available:
            return "Apple Intelligence ready"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings"
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is still preparing"
        case .unavailable:
            return "Apple Intelligence unavailable"
        }
    }

    func plan(prompt: String, project: StudioProject) async throws -> NativeScreenPlan {
        guard model.isAvailable else {
            throw PlannerError.modelUnavailable(availabilityText)
        }

        let existing = project.components.map {
            "\($0.kind.rawValue):\($0.text)@\(Int($0.x)),\(Int($0.y)) \(Int($0.width))x\(Int($0.height))"
        }.joined(separator: "; ")

        let instructions = """
        You are the layout planner inside ReyForge, a native SwiftUI visual app builder.
        Never write Swift source code. Instead design the screen by selecting native controls,
        deciding hierarchy, position, size, and one useful primary interaction for each control.

        Use familiar Apple interface patterns. For broad requests such as 'create a dashboard',
        infer the expected information architecture instead of asking for every component.
        A dashboard normally needs a clear title, compact KPI/summary elements, a visual status or
        progress area when appropriate, recent activity or list content, and a primary action.
        A settings screen normally uses grouped settings controls. Authentication uses fields plus
        a primary sign-in action. Profiles use identity, metadata, editable content, and actions.

        Canvas is 390x844 points. Keep every component within bounds. Use readable spacing,
        avoid overlap, keep touch controls at least 44 points tall, and prefer widths near 320-350
        for full-width controls. Place elements from top to bottom with sensible visual hierarchy.
        Do not add decorative elements unless they help the requested screen.
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let request = """
        App name: \(project.name)
        Existing screen: \(existing.isEmpty ? "empty" : existing)
        User request: \(prompt)

        Produce the complete native screen plan that best satisfies the request.
        """

        let response = try await session.respond(
            to: request,
            generating: NativeScreenPlan.self
        )
        return response.content
    }

    func apply(_ plan: NativeScreenPlan, to project: inout StudioProject) -> [StudioComponent] {
        let converted = plan.components.map(Self.convert)
        if plan.replaceExisting {
            project.components = converted
        } else {
            project.components.append(contentsOf: converted)
        }
        return converted
    }

    static func fallbackDashboard() -> NativeScreenPlan {
        NativeScreenPlan(
            summary: "Native dashboard with summary, progress, recent activity, and a primary action.",
            replaceExisting: true,
            components: [
                .init(kind: .text, text: "Dashboard", detail: "", x: 195, y: 70, width: 330, height: 48, action: .none, actionKey: "", actionValue: ""),
                .init(kind: .gauge, text: "Goal Progress", detail: "", x: 105, y: 165, width: 160, height: 110, action: .none, actionKey: "", actionValue: ""),
                .init(kind: .progress, text: "Completion", detail: "", x: 285, y: 165, width: 160, height: 110, action: .none, actionKey: "", actionValue: ""),
                .init(kind: .label, text: "This Week", detail: "chart.bar.fill", x: 195, y: 255, width: 330, height: 48, action: .none, actionKey: "", actionValue: ""),
                .init(kind: .list, text: "Recent Activity", detail: "", x: 195, y: 430, width: 340, height: 260, action: .none, actionKey: "", actionValue: ""),
                .init(kind: .button, text: "Add Item", detail: "", x: 195, y: 610, width: 330, height: 52, action: .showAlert, actionKey: "New Item", actionValue: "Create a new dashboard item")
            ]
        )
    }

    private static func convert(_ planned: PlannedComponent) -> StudioComponent {
        let kind: StudioComponentKind
        switch planned.kind {
        case .text: kind = .text
        case .button: kind = .button
        case .textField: kind = .textField
        case .secureField: kind = .secureField
        case .textEditor: kind = .textEditor
        case .image: kind = .image
        case .symbol: kind = .symbol
        case .label: kind = .label
        case .toggle: kind = .toggle
        case .slider: kind = .slider
        case .stepper: kind = .stepper
        case .picker: kind = .picker
        case .datePicker: kind = .datePicker
        case .progress: kind = .progress
        case .gauge: kind = .gauge
        case .divider: kind = .divider
        case .link: kind = .link
        case .menu: kind = .menu
        case .navigationLink: kind = .navigationLink
        case .list: kind = .list
        case .scrollView: kind = .scrollView
        case .vStack: kind = .vStack
        case .hStack: kind = .hStack
        case .zStack: kind = .zStack
        case .form: kind = .form
        case .section: kind = .section
        case .roundedRectangle: kind = .roundedRectangle
        case .circle: kind = .circle
        case .webView: kind = .webView
        case .map: kind = .map
        case .shareLink: kind = .shareLink
        }

        var component = StudioComponent.make(kind)
        component.text = planned.text
        component.detail = planned.detail
        component.width = min(max(44, Double(planned.width)), 370)
        component.height = min(max(28, Double(planned.height)), 700)
        component.x = min(max(component.width / 2, Double(planned.x)), 390 - component.width / 2)
        component.y = min(max(component.height / 2, Double(planned.y)), 844 - component.height / 2)

        if let actionKind = convertAction(planned.action), !planned.actionKey.isEmpty || !planned.actionValue.isEmpty {
            component.actions = [StudioAction(kind: actionKind, key: planned.actionKey, value: planned.actionValue)]
        }
        return component
    }

    private static func convertAction(_ action: PlannedActionKind) -> StudioActionKind? {
        switch action {
        case .none: return nil
        case .showAlert: return .showAlert
        case .navigate: return .navigate
        case .setVariable: return .setVariable
        case .toggleVariable: return .toggleVariable
        case .increment: return .increment
        case .decrement: return .decrement
        case .openURL: return .openURL
        case .saveLocal: return .saveLocal
        case .apiGET: return .apiGET
        case .copyText: return .copyText
        }
    }
}

enum PlannerError: LocalizedError {
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let message): return message
        }
    }
}
