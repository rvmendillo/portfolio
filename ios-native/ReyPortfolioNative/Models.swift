import SwiftUI

enum NativeAppKind: String, CaseIterable, Identifiable {
    case about, resume, projects, files, browser, terminal, ide, designer, transpiler, assistant, studio, settings, calculator

    var id: String { rawValue }
    var title: String {
        switch self {
        case .about: return "About Rey"
        case .resume: return "Resume"
        case .projects: return "Projects"
        case .files: return "Files"
        case .browser: return "Browser"
        case .terminal: return "Terminal"
        case .ide: return "Rey IDE"
        case .designer: return "GUI Designer"
        case .transpiler: return "Transpiler"
        case .assistant: return "Local AI"
        case .studio: return "App Studio"
        case .settings: return "Settings"
        case .calculator: return "Calculator"
        }
    }
    var subtitle: String {
        switch self {
        case .about: return "Profile & experience"
        case .resume: return "Native PDF viewer"
        case .projects: return "Selected work"
        case .files: return "Portfolio library"
        case .browser: return "Native links"
        case .terminal: return "Safe local commands"
        case .ide: return "Code workspace"
        case .designer: return "Visual app builder"
        case .transpiler: return "Python & HumanCode"
        case .assistant: return "Offline knowledge"
        case .studio: return "Installed designs"
        case .settings: return "Themes & profile"
        case .calculator: return "Safe arithmetic"
        }
    }
    var symbol: String {
        switch self {
        case .about: return "person.crop.square.filled.and.at.rectangle"
        case .resume: return "doc.text.fill"
        case .projects: return "square.stack.3d.up.fill"
        case .files: return "folder.fill"
        case .browser: return "safari.fill"
        case .terminal: return "terminal.fill"
        case .ide: return "chevron.left.forwardslash.chevron.right"
        case .designer: return "square.on.square.dashed"
        case .transpiler: return "arrow.left.arrow.right.square.fill"
        case .assistant: return "sparkles"
        case .studio: return "shippingbox.fill"
        case .settings: return "gearshape.fill"
        case .calculator: return "plus.forwardslash.minus"
        }
    }
    var tint: Color {
        switch self {
        case .about: return .cyan
        case .resume: return .red
        case .projects: return .purple
        case .files: return .yellow
        case .browser: return .blue
        case .terminal: return .gray
        case .ide: return .pink
        case .designer: return .mint
        case .transpiler: return .orange
        case .assistant: return .indigo
        case .studio: return .teal
        case .settings: return .secondary
        case .calculator: return .orange
        }
    }
}

enum PortfolioTheme: String, CaseIterable, Identifiable {
    case windows, ios, resume
    var id: String { rawValue }
    var title: String { rawValue == "ios" ? "iOS" : rawValue.capitalized }
    var subtitle: String {
        switch self { case .windows: return "Aurora glass"; case .ios: return "Fluid color"; case .resume: return "Paper & ink" }
    }
}

struct ProjectItem: Identifiable {
    let id = UUID()
    let number: String
    let category: String
    let title: String
    let summary: String
    let tags: [String]
}

let portfolioProjects = [
    ProjectItem(number: "01", category: "DIGITAL CARGO", title: "Skyler", summary: "A ONE Record trust engine harmonizing dangerous-goods compliance and shipment-level JSON-LD for ground-handler checks.", tags: ["ONE Record", "JSON-LD", "DG"]),
    ProjectItem(number: "02", category: "COMPUTER VISION", title: "Gesture Cursor", summary: "Cursor movement translation through real-time gesture detection and deep-learning landmarks.", tags: ["Python", "Vision", "Deep Learning"]),
    ProjectItem(number: "03", category: "PREDICTIVE ANALYTICS", title: "Rotational Churn", summary: "Automated modeling and cosine similarity used to understand and predict rotational churn.", tags: ["PyCaret", "ML", "Analytics"]),
    ProjectItem(number: "04", category: "NATURAL LANGUAGE", title: "Text Summarization", summary: "Extractive and abstractive summarization using similarity graphs and PageRank.", tags: ["NLP", "PageRank", "Python"])
]

enum DesignerNodeKind: String, CaseIterable, Codable, Identifiable {
    case label, input, button, output
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .label: return "textformat"; case .input: return "rectangle.and.pencil.and.ellipsis"; case .button: return "rectangle.fill"; case .output: return "equal.square" }
    }
}

enum DesignerOperation: String, CaseIterable, Codable, Identifiable {
    case none, add, subtract, multiply, divide, formula, join, uppercase, lowercase, clear
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct DesignerNode: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var kind: DesignerNodeKind
    var text: String
    var x: Double
    var y: Double
    var operation: DesignerOperation
    var formula: String

    init(kind: DesignerNodeKind, index: Int, x: Double = 100, y: Double = 100) {
        id = UUID(); name = "\(kind.rawValue)\(index)"; self.kind = kind
        text = kind == .button ? "Calculate" : kind == .output ? "Result" : kind == .input ? "Input" : "Label"
        self.x = x; self.y = y; operation = .none; formula = ""
    }
}

struct DesignerConnection: Identifiable, Codable, Equatable {
    var id = UUID()
    var from: UUID
    var to: UUID
}

struct NativePackage: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var nodes: [DesignerNode]
    var connections: [DesignerConnection]
    var installedAt = Date()
}
