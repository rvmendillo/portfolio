import Foundation

enum SafeMathError: LocalizedError {
    case invalidExpression, unknownValue(String), divisionByZero
    var errorDescription: String? {
        switch self { case .invalidExpression: return "Invalid expression"; case .unknownValue(let name): return "Unknown value: \(name)"; case .divisionByZero: return "Division by zero" }
    }
}

enum SafeMath {
    static func evaluate(_ source: String, variables: [String: Double] = [:]) throws -> Double {
        guard source.count <= 180, source.allSatisfy({ $0.isNumber || $0.isLetter || $0 == "_" || "+-*/%.() \t".contains($0) }) else { throw SafeMathError.invalidExpression }
        var parser = Parser(Array(source), variables: variables)
        let result = try parser.expression()
        parser.skipSpaces()
        guard parser.index == parser.characters.count, result.isFinite else { throw SafeMathError.invalidExpression }
        return result
    }

    private struct Parser {
        let characters: [Character]
        let variables: [String: Double]
        var index = 0

        init(_ characters: [Character], variables: [String: Double]) { self.characters = characters; self.variables = variables }
        mutating func skipSpaces() { while index < characters.count && characters[index].isWhitespace { index += 1 } }
        mutating func match(_ character: Character) -> Bool { skipSpaces(); guard index < characters.count, characters[index] == character else { return false }; index += 1; return true }
        mutating func expression() throws -> Double {
            var value = try term()
            while true { if match("+") { value += try term() } else if match("-") { value -= try term() } else { return value } }
        }
        mutating func term() throws -> Double {
            var value = try factor()
            while true {
                if match("*") { value *= try factor() }
                else if match("/") { let rhs = try factor(); guard rhs != 0 else { throw SafeMathError.divisionByZero }; value /= rhs }
                else if match("%") { let rhs = try factor(); guard rhs != 0 else { throw SafeMathError.divisionByZero }; value.formTruncatingRemainder(dividingBy: rhs) }
                else { return value }
            }
        }
        mutating func factor() throws -> Double {
            skipSpaces()
            if match("-") { return -(try factor()) }
            if match("+") { return try factor() }
            if match("(") { let value = try expression(); guard match(")") else { throw SafeMathError.invalidExpression }; return value }
            guard index < characters.count else { throw SafeMathError.invalidExpression }
            if characters[index].isNumber || characters[index] == "." {
                let start = index
                while index < characters.count && (characters[index].isNumber || characters[index] == ".") { index += 1 }
                guard let number = Double(String(characters[start..<index])) else { throw SafeMathError.invalidExpression }
                return number
            }
            if characters[index].isLetter || characters[index] == "_" {
                let start = index
                while index < characters.count && (characters[index].isLetter || characters[index].isNumber || characters[index] == "_") { index += 1 }
                let name = String(characters[start..<index]); guard let value = variables[name] else { throw SafeMathError.unknownValue(name) }; return value
            }
            throw SafeMathError.invalidExpression
        }
    }
}

enum MathFormatter {
    static func string(_ value: Double) -> String {
        if value.isFinite && value.rounded() == value && value > Double(Int.min) && value < Double(Int.max) { return String(Int(value)) }
        return String(format: "%.8f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

enum NativeCommandEngine {
    static func execute(_ command: String, theme: ThemeStore) -> String {
        let clean = String(command.prefix(1_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = clean.split(separator: " ", maxSplits: 1).map(String.init), name = pieces.first?.lowercased() ?? "", args = pieces.count > 1 ? pieces[1] : ""
        switch name {
        case "help": return "help · whoami · about · skills · projects · dir · date · calc <expression> · theme <windows|ios|resume> · security · neofetch"
        case "whoami": return "Rey Victor Mendillo — Software Engineer / AI builder"
        case "about": return "Enterprise software, AI/ML, thoughtful interfaces, mathematics, and creative systems."
        case "skills": return "Java · Spring · Angular · TypeScript · Python · AI/ML · NLP · Computer Vision · Oracle · OAuth"
        case "projects": return "Skyler · Gesture Cursor · Rotational Churn · Text Summarization"
        case "dir", "ls": return "Resume.pdf\nProjects/\nDeveloper/\nGUI Designer.native\nTranspiler.native"
        case "date": return Date().formatted(date: .complete, time: .standard)
        case "calc": do { return MathFormatter.string(try SafeMath.evaluate(args)) } catch { return error.localizedDescription }
        case "theme": if let value = PortfolioTheme(rawValue: args.lowercased()) { theme.selectedTheme = value; return "Theme changed to \(value.title)." }; return "Choose windows, ios, or resume."
        case "security": return "Native SwiftUI · local settings · bounded execution · validated packages · review code before running"
        case "neofetch": return "▣ Rey Portfolio Native\nTheme: \(theme.selectedTheme.title)\nRuntime: SwiftUI\nProfile: \(theme.profileName)\nLocal AI: Load the bundled model in the assistant"
        case "echo": return String(args.prefix(600))
        case "clear": return "__CLEAR__"
        default: return "'\(String(name.prefix(40)))' is not recognized. Type 'help'."
        }
    }
}

enum NativeTranspiler {
    static let samples: [String: String] = [
        "Python": "name = \"Rey\"\nprint(\"Portfolio Native\")\nfor i in range(3):\n    print(i)",
        "HumanCode EN": "set name to \"Rey\"\nsay \"Welcome, \" + name\nrepeat 3 times\n    say \"Building natively\"\nend",
        "HumanCode FIL": "itakda pangalan bilang \"Rey\"\nipakita \"Kumusta, \" + pangalan\nulitin 3 beses\n    ipakita \"Lokal na bumubuo\"\nwakas",
        "GUI YAML": "app: Native Calculator\ncomponents:\n  - id: input1\n    type: input\n  - id: calculate\n    type: button\n    operation: add\n  - id: result\n    type: output\nconnections:\n  - input1 -> calculate\n  - calculate -> result"
    ]
    static func compile(source: String, input: String, target: String, customPrint: String) -> String {
        if input == "GUI YAML" { return guiTarget(source, target: target) }
        let python = input == "Python" ? source : humanToPython(source, filipino: input.contains("FIL"), customPrint: customPrint)
        if target == "Python" { return python }
        return "Open Transpiler to compile Python to Java or C++ with the AST compiler."
    }
    static func humanToPython(_ source: String, filipino: Bool, customPrint: String) -> String {
        let say = filipino ? ["ipakita", "ilabas"] : ["say", "show", "display", customPrint.lowercased()].filter { !$0.isEmpty }
        let setWords = filipino ? ["itakda", "ilagay"] : ["set"]
        let endWords = filipino ? ["wakas", "tapusin"] : ["end"]
        var indent = 0, result = ["# HumanCode compiled locally to native Python", ""]
        for raw in source.prefix(40_000).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if endWords.contains(where: { line.lowercased() == $0 }) { indent = max(0, indent - 1); continue }
            let lower = line.lowercased(); var compiled = line; var opens = false
            if let keyword = say.first(where: { lower == $0 || lower.hasPrefix($0 + " ") }) { compiled = "print(\(line.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)))" }
            else if let keyword = setWords.first(where: { lower.hasPrefix($0 + " ") }) {
                let body = String(line.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                let separators = filipino ? [" bilang ", " ay "] : [" to "]
                if let separator = separators.first(where: { body.lowercased().contains($0) }), let range = body.lowercased().range(of: separator) { compiled = "\(body[..<range.lowerBound]) = \(body[range.upperBound...])" }
            } else if lower.hasPrefix(filipino ? "ulitin " : "repeat ") { let body = line.split(separator: " ").dropFirst().dropLast().joined(separator: " "); compiled = "for _ in range(\(body)):"; opens = true }
            else if lower.hasPrefix(filipino ? "kung " : "if ") { let prefix = filipino ? 5 : 3; compiled = "if \(line.dropFirst(prefix).replacingOccurrences(of: " then", with: "")):"; opens = true }
            else if lower == (filipino ? "kundi" : "else") { indent = max(0, indent - 1); compiled = "else:"; opens = true }
            else if lower.hasPrefix(filipino ? "gawain " : "function ") { let prefix = filipino ? 7 : 9; compiled = "def \(line.dropFirst(prefix).replacingOccurrences(of: " with ", with: "(").replacingOccurrences(of: " gamit ", with: "("))"; if !compiled.contains("(") { compiled += "()" }; if !compiled.hasSuffix(")") { compiled += ")" }; compiled += ":"; opens = true }
            result.append(String(repeating: "    ", count: indent) + compiled); if opens { indent += 1 }
        }
        return result.joined(separator: "\n")
    }
    private struct GUIComponent {
        var id = "component"
        var type = "label"
        var text = ""
        var operation = "none"
        var formula = ""
        var x = 20
        var y = 20
    }

    private struct GUIConnection {
        let from: String
        let to: String
    }

    private static func guiTarget(_ source: String, target: String) -> String {
        let parsed = parseGUI(source)
        guard !parsed.components.isEmpty else {
            return "// No GUI components found. Use the YAML generated by GUI Designer."
        }
        switch target {
        case "Tkinter": return tkinter(parsed.components, parsed.connections)
        case "PyQt": return pyqt(parsed.components, parsed.connections)
        case "Kivy": return kivy(parsed.components, parsed.connections)
        case "Java", "Java Swing": return javaSwing(parsed.components, parsed.connections)
        case "Python": return tkinter(parsed.components, parsed.connections)
        case "C++":
            return """
            // GUI YAML converted locally to C++.
            // The native iOS transpiler keeps GUI bindings explicit; use Qt/wxWidgets/Win32 as your desktop toolkit.
            // For ready-to-run generated GUI code, choose Tkinter, PyQt, Kivy, or Java Swing.
            
            \(source)
            """
        default:
            return "# GUI YAML converted locally to \(target)\n\(source)"
        }
    }

    private static func parseGUI(_ source: String) -> (components: [GUIComponent], connections: [GUIConnection]) {
        var components: [GUIComponent] = []
        var connections: [GUIConnection] = []
        var current: GUIComponent?
        var inConnections = false
        var pendingFrom: String?

        func clean(_ value: Substring) -> String {
            String(value).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        }

        for raw in source.prefix(60_000).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "connections:" {
                if let item = current { components.append(item); current = nil }
                inConnections = true
                continue
            }

            if inConnections {
                if line.hasPrefix("- from:") {
                    pendingFrom = clean(line.dropFirst("- from:".count))
                } else if line.hasPrefix("to:"), let from = pendingFrom {
                    connections.append(GUIConnection(from: from, to: clean(line.dropFirst("to:".count))))
                    pendingFrom = nil
                } else if line.hasPrefix("- "), line.contains("->") {
                    let body = line.dropFirst(2).split(separator: ">", maxSplits: 1)
                    if body.count == 2 {
                        let from = String(body[0]).replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces)
                        let to = String(body[1]).trimmingCharacters(in: .whitespaces)
                        connections.append(GUIConnection(from: from, to: to))
                    }
                }
                continue
            }

            if line.hasPrefix("- id:") {
                if let item = current { components.append(item) }
                var item = GUIComponent()
                item.id = clean(line.dropFirst("- id:".count))
                current = item
                continue
            }
            guard var item = current else { continue }
            if line.hasPrefix("type:") { item.type = clean(line.dropFirst("type:".count)) }
            else if line.hasPrefix("text:") { item.text = clean(line.dropFirst("text:".count)) }
            else if line.hasPrefix("operation:") { item.operation = clean(line.dropFirst("operation:".count)) }
            else if line.hasPrefix("formula:") { item.formula = clean(line.dropFirst("formula:".count)) }
            else if line.hasPrefix("x:") { item.x = Int(clean(line.dropFirst("x:".count))) ?? item.x }
            else if line.hasPrefix("y:") { item.y = Int(clean(line.dropFirst("y:".count))) ?? item.y }
            current = item
        }
        if let item = current { components.append(item) }
        return (components, connections)
    }

    private static func ident(_ value: String) -> String {
        var result = value.map { $0.isLetter || $0.isNumber || $0 == "_" ? String($0) : "_" }.joined()
        if result.isEmpty { result = "component" }
        if result.first?.isNumber == true { result = "_" + result }
        return result
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static func incoming(_ button: GUIComponent, _ connections: [GUIConnection]) -> [String] {
        connections.filter { $0.to == button.id }.map(\.from)
    }

    private static func outgoing(_ button: GUIComponent, _ connections: [GUIConnection]) -> [String] {
        connections.filter { $0.from == button.id }.map(\.to)
    }

    private static func pythonExpression(_ button: GUIComponent, inputs: [String], getter: (String) -> String) -> String {
        let numeric = inputs.enumerated().map { "num(\(getter($0.element)))" }
        let raw = inputs.map(getter)
        switch button.operation {
        case "add": return numeric.isEmpty ? "0" : numeric.joined(separator: " + ")
        case "subtract":
            guard let first = numeric.first else { return "0" }
            return numeric.dropFirst().reduce(first) { "\($0) - \($1)" }
        case "multiply": return numeric.isEmpty ? "0" : numeric.joined(separator: " * ")
        case "divide":
            guard let first = numeric.first else { return "0" }
            return numeric.dropFirst().reduce(first) { "\($0) / (\($1) or 1)" }
        case "join": return raw.isEmpty ? "''" : raw.joined(separator: " + ' ' + ")
        case "uppercase": return raw.first.map { "\($0).upper()" } ?? "''"
        case "lowercase": return raw.first.map { "\($0).lower()" } ?? "''"
        case "formula":
            var expression = button.formula.isEmpty ? "0" : button.formula
            for (index, input) in inputs.enumerated() {
                expression = expression.replacingOccurrences(of: input, with: "__VALUE_\(index)__")
                expression = expression.replacingOccurrences(of: "input\(index + 1)", with: "__VALUE_\(index)__")
            }
            for (index, input) in inputs.enumerated() {
                expression = expression.replacingOccurrences(of: "__VALUE_\(index)__", with: "num(\(getter(input)))")
            }
            return expression
        default: return raw.first ?? "''"
        }
    }

    private static func tkinter(_ components: [GUIComponent], _ connections: [GUIConnection]) -> String {
        var out = [
            "import tkinter as tk",
            "from tkinter import ttk",
            "",
            "def num(value):",
            "    try: return float(value)",
            "    except (TypeError, ValueError): return 0.0",
            "",
            "root = tk.Tk()",
            "root.title(\"Generated App\")",
            "root.geometry(\"520x420\")",
            ""
        ]

        for component in components {
            let id = ident(component.id)
            switch component.type {
            case "input":
                out += ["\(id)_var = tk.StringVar()", "\(id) = ttk.Entry(root, textvariable=\(id)_var)", "\(id).place(x=\(component.x), y=\(component.y), width=140)"]
            case "output":
                out += ["\(id)_var = tk.StringVar(value=\(quoted(component.text)))", "\(id) = ttk.Label(root, textvariable=\(id)_var)", "\(id).place(x=\(component.x), y=\(component.y), width=140)"]
            case "button":
                break
            default:
                out += ["\(id) = ttk.Label(root, text=\(quoted(component.text)))", "\(id).place(x=\(component.x), y=\(component.y))"]
            }
            out.append("")
        }

        for button in components where button.type == "button" {
            let id = ident(button.id)
            let inputs = incoming(button, connections)
            let outputs = outgoing(button, connections)
            out.append("def action_\(id)():")
            if button.operation == "clear" {
                if inputs.isEmpty { out.append("    pass") }
                for input in inputs { out.append("    \(ident(input))_var.set(\"\")") }
                for output in outputs { out.append("    \(ident(output))_var.set(\"\")") }
            } else {
                let expr = pythonExpression(button, inputs: inputs) { "\(ident($0))_var.get()" }
                out.append("    result = \(expr)")
                if outputs.isEmpty { out.append("    print(result)") }
                for output in outputs { out.append("    \(ident(output))_var.set(str(result))") }
            }
            out += ["\(id) = ttk.Button(root, text=\(quoted(button.text)), command=action_\(id))", "\(id).place(x=\(button.x), y=\(button.y), width=120)", ""]
        }
        out += ["root.mainloop()"]
        return out.joined(separator: "\n")
    }

    private static func pyqt(_ components: [GUIComponent], _ connections: [GUIConnection]) -> String {
        var out = [
            "import sys",
            "from PyQt6.QtWidgets import QApplication, QWidget, QLineEdit, QPushButton, QLabel",
            "",
            "def num(value):",
            "    try: return float(value)",
            "    except (TypeError, ValueError): return 0.0",
            "",
            "app = QApplication(sys.argv)",
            "window = QWidget()",
            "window.setWindowTitle(\"Generated App\")",
            "window.resize(520, 420)",
            ""
        ]
        for component in components {
            let id = ident(component.id)
            switch component.type {
            case "input":
                out += ["\(id) = QLineEdit(window)", "\(id).setPlaceholderText(\(quoted(component.text)))", "\(id).setGeometry(\(component.x), \(component.y), 140, 32)"]
            case "output":
                out += ["\(id) = QLabel(\(quoted(component.text)), window)", "\(id).setGeometry(\(component.x), \(component.y), 160, 32)"]
            case "button": break
            default:
                out += ["\(id) = QLabel(\(quoted(component.text)), window)", "\(id).setGeometry(\(component.x), \(component.y), 160, 32)"]
            }
            out.append("")
        }
        for button in components where button.type == "button" {
            let id = ident(button.id)
            let inputs = incoming(button, connections)
            let outputs = outgoing(button, connections)
            out.append("def action_\(id)():")
            if button.operation == "clear" {
                if inputs.isEmpty { out.append("    pass") }
                for input in inputs { out.append("    \(ident(input)).clear()") }
                for output in outputs { out.append("    \(ident(output)).setText(\"\")") }
            } else {
                let expr = pythonExpression(button, inputs: inputs) { "\(ident($0)).text()" }
                out.append("    result = \(expr)")
                if outputs.isEmpty { out.append("    print(result)") }
                for output in outputs { out.append("    \(ident(output)).setText(str(result))") }
            }
            out += ["\(id) = QPushButton(\(quoted(button.text)), window)", "\(id).setGeometry(\(button.x), \(button.y), 120, 32)", "\(id).clicked.connect(action_\(id))", ""]
        }
        out += ["window.show()", "sys.exit(app.exec())"]
        return out.joined(separator: "\n")
    }

    private static func kivy(_ components: [GUIComponent], _ connections: [GUIConnection]) -> String {
        var out = [
            "from kivy.app import App",
            "from kivy.uix.floatlayout import FloatLayout",
            "from kivy.uix.textinput import TextInput",
            "from kivy.uix.button import Button",
            "from kivy.uix.label import Label",
            "",
            "def num(value):",
            "    try: return float(value)",
            "    except (TypeError, ValueError): return 0.0",
            "",
            "class GeneratedApp(App):",
            "    def build(self):",
            "        root = FloatLayout()"
        ]
        for component in components {
            let id = ident(component.id)
            switch component.type {
            case "input":
                out += ["        self.\(id) = TextInput(hint_text=\(quoted(component.text)), multiline=False, size_hint=(None, None), size=(140, 40), pos=(\(component.x), \(component.y)))", "        root.add_widget(self.\(id))"]
            case "output":
                out += ["        self.\(id) = Label(text=\(quoted(component.text)), size_hint=(None, None), size=(160, 40), pos=(\(component.x), \(component.y)))", "        root.add_widget(self.\(id))"]
            case "button":
                out += ["        self.\(id) = Button(text=\(quoted(component.text)), size_hint=(None, None), size=(120, 42), pos=(\(component.x), \(component.y)))", "        self.\(id).bind(on_release=self.action_\(id))", "        root.add_widget(self.\(id))"]
            default:
                out += ["        self.\(id) = Label(text=\(quoted(component.text)), size_hint=(None, None), size=(160, 40), pos=(\(component.x), \(component.y)))", "        root.add_widget(self.\(id))"]
            }
        }
        out += ["        return root", ""]
        for button in components where button.type == "button" {
            let id = ident(button.id)
            let inputs = incoming(button, connections)
            let outputs = outgoing(button, connections)
            out.append("    def action_\(id)(self, _button):")
            if button.operation == "clear" {
                if inputs.isEmpty { out.append("        pass") }
                for input in inputs { out.append("        self.\(ident(input)).text = \"\"") }
                for output in outputs { out.append("        self.\(ident(output)).text = \"\"") }
            } else {
                let expr = pythonExpression(button, inputs: inputs) { "self.\(ident($0)).text" }
                out.append("        result = \(expr)")
                if outputs.isEmpty { out.append("        print(result)") }
                for output in outputs { out.append("        self.\(ident(output)).text = str(result)") }
            }
            out.append("")
        }
        out += ["GeneratedApp().run()"]
        return out.joined(separator: "\n")
    }

    private static func javaSwing(_ components: [GUIComponent], _ connections: [GUIConnection]) -> String {
        var out = [
            "import javax.swing.*;",
            "",
            "public class GeneratedApp {",
            "  static double num(String value) {",
            "    try { return Double.parseDouble(value); } catch (Exception ignored) { return 0.0; }",
            "  }",
            "",
            "  public static void main(String[] args) {",
            "    SwingUtilities.invokeLater(() -> {",
            "      JFrame frame = new JFrame(\"Generated App\");",
            "      frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);",
            "      frame.setSize(540, 460);",
            "      frame.setLayout(null);"
        ]
        for component in components {
            let id = ident(component.id)
            switch component.type {
            case "input":
                out += ["      JTextField \(id) = new JTextField();", "      \(id).setToolTipText(\(quoted(component.text)));", "      \(id).setBounds(\(component.x), \(component.y), 140, 32);", "      frame.add(\(id));"]
            case "output":
                out += ["      JLabel \(id) = new JLabel(\(quoted(component.text)));", "      \(id).setBounds(\(component.x), \(component.y), 160, 32);", "      frame.add(\(id));"]
            case "button":
                out += ["      JButton \(id) = new JButton(\(quoted(component.text)));", "      \(id).setBounds(\(component.x), \(component.y), 120, 32);", "      frame.add(\(id));"]
            default:
                out += ["      JLabel \(id) = new JLabel(\(quoted(component.text)));", "      \(id).setBounds(\(component.x), \(component.y), 160, 32);", "      frame.add(\(id));"]
            }
        }
        out.append("")
        for button in components where button.type == "button" {
            let id = ident(button.id)
            let inputs = incoming(button, connections)
            let outputs = outgoing(button, connections)
            out.append("      \(id).addActionListener(e -> {")
            if button.operation == "clear" {
                for input in inputs { out.append("        \(ident(input)).setText(\"\");") }
                for output in outputs { out.append("        \(ident(output)).setText(\"\");") }
                if inputs.isEmpty && outputs.isEmpty { out.append("        // No connected fields to clear.") }
            } else if ["join", "uppercase", "lowercase", "none"].contains(button.operation) {
                let raw = inputs.map { "\(ident($0)).getText()" }
                let expr: String
                if button.operation == "join" { expr = raw.isEmpty ? "\"\"" : raw.joined(separator: " + \" \" + ") }
                else if button.operation == "uppercase" { expr = raw.first.map { "\($0).toUpperCase()" } ?? "\"\"" }
                else if button.operation == "lowercase" { expr = raw.first.map { "\($0).toLowerCase()" } ?? "\"\"" }
                else { expr = raw.first ?? "\"\"" }
                out.append("        String result = \(expr);")
                if outputs.isEmpty { out.append("        System.out.println(result);") }
                for output in outputs { out.append("        \(ident(output)).setText(result);") }
            } else {
                let nums = inputs.map { "num(\(ident($0)).getText())" }
                let expr: String
                switch button.operation {
                case "add": expr = nums.isEmpty ? "0.0" : nums.joined(separator: " + ")
                case "subtract":
                    if let first = nums.first { expr = nums.dropFirst().reduce(first) { "\($0) - \($1)" } } else { expr = "0.0" }
                case "multiply": expr = nums.isEmpty ? "0.0" : nums.joined(separator: " * ")
                case "divide":
                    if let first = nums.first { expr = nums.dropFirst().reduce(first) { "\($0) / ((\($1)) == 0 ? 1 : (\($1)))" } } else { expr = "0.0" }
                case "formula":
                    var formula = button.formula.isEmpty ? "0.0" : button.formula
                    for (index, input) in inputs.enumerated() {
                        formula = formula.replacingOccurrences(of: input, with: "__VALUE_\(index)__")
                        formula = formula.replacingOccurrences(of: "input\(index + 1)", with: "__VALUE_\(index)__")
                    }
                    for (index, input) in inputs.enumerated() {
                        formula = formula.replacingOccurrences(of: "__VALUE_\(index)__", with: "num(\(ident(input)).getText())")
                    }
                    expr = formula
                default: expr = nums.first ?? "0.0"
                }
                out.append("        double result = \(expr);")
                if outputs.isEmpty { out.append("        System.out.println(result);") }
                for output in outputs { out.append("        \(ident(output)).setText(Double.toString(result));") }
            }
            out.append("      });")
        }
        out += ["", "      frame.setVisible(true);", "    });", "  }", "}"]
        return out.joined(separator: "\n")
    }
}
