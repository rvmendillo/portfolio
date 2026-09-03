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
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.8f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

enum SafeCodeRuntime {
    static func run(_ source: String, language: String) -> String {
        let lines = source.prefix(20_000).split(whereSeparator: \.isNewline).prefix(400)
        var numbers: [String: Double] = [:]
        var strings: [String: String] = [:]
        var output: [String] = []
        for raw in lines {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if line.hasSuffix(";") { line.removeLast() }
            if let content = printableContent(line) {
                output.append(content.split(separator: ",", omittingEmptySubsequences: false).map { render(String($0), numbers: numbers, strings: strings) }.joined(separator: " "))
                continue
            }
            let pieces = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pieces.count == 2, !line.contains("==") {
                let rawName = pieces[0].trimmingCharacters(in: .whitespaces).split(separator: " ").last.map(String.init) ?? "value"
                let name = rawName.replacingOccurrences(of: "self.", with: "")
                let value = pieces[1].trimmingCharacters(in: .whitespaces)
                if let number = try? SafeMath.evaluate(value, variables: numbers) { numbers[name] = number }
                else { strings[name] = unquote(value) }
            }
        }
        return output.isEmpty ? "\(language) source parsed safely. No printable output." : output.joined(separator: "\n")
    }
    private static func printableContent(_ line: String) -> String? {
        let wrappers = ["print(", "console.log(", "System.out.println("]
        for wrapper in wrappers where line.hasPrefix(wrapper) && line.hasSuffix(")") { return String(line.dropFirst(wrapper.count).dropLast()) }
        if let range = line.range(of: "cout <<") { return String(line[range.upperBound...]).replacingOccurrences(of: "<< endl", with: "").replacingOccurrences(of: "<< std::endl", with: "").replacingOccurrences(of: "<<", with: ",") }
        if let range = line.range(of: "std::cout <<") { return String(line[range.upperBound...]).replacingOccurrences(of: "<< std::endl", with: "").replacingOccurrences(of: "<<", with: ",") }
        return nil
    }
    private static func render(_ raw: String, numbers: [String: Double], strings: [String: String]) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) { return unquote(value) }
        if let string = strings[value] { return string }
        if let number = numbers[value] { return MathFormatter.string(number) }
        if let number = try? SafeMath.evaluate(value, variables: numbers) { return MathFormatter.string(number) }
        return String(value.prefix(300))
    }
    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last, (first == "\"" && last == "\"") || (first == "'" && last == "'") else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\n", with: "\n")
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
        case "security": return "Native SwiftUI · no eval · local-only settings · safe arithmetic · bounded inputs · validated packages"
        case "neofetch": return "▣ Rey Portfolio Native\nTheme: \(theme.selectedTheme.title)\nRuntime: SwiftUI\nProfile: \(theme.profileName)\nLocal AI: Ready"
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
        return target == "C++" ? pythonToCpp(python) : pythonToJava(python)
    }
    private static func humanToPython(_ source: String, filipino: Bool, customPrint: String) -> String {
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
    private static func pythonToJava(_ source: String) -> String {
        var out = ["// Generated locally by Rey Portfolio Native", "import java.util.*;", "", "public class Main {", "  public static void main(String[] args) {"]
        for raw in source.split(whereSeparator: \.isNewline) { let line = raw.trimmingCharacters(in: .whitespaces); if line.hasPrefix("print(") { out.append("    System.out.println(\(line.dropFirst(6).dropLast()));") } else if line.contains(" = ") { out.append("    var \(line.replacingOccurrences(of: "True", with: "true").replacingOccurrences(of: "False", with: "false"));") } else if line.hasPrefix("for ") { out.append("    // Native Java loop: \(line)") } else if line.hasPrefix("class ") || line.hasPrefix("def ") || line.hasPrefix("@") { out.append("    // Object/function feature: \(line)") } }
        out += ["  }", "}"]; return out.joined(separator: "\n")
    }
    private static func pythonToCpp(_ source: String) -> String {
        var out = ["// Generated locally by Rey Portfolio Native", "#include <iostream>", "#include <string>", "#include <vector>", "", "int main() {"]
        for raw in source.split(whereSeparator: \.isNewline) { let line = raw.trimmingCharacters(in: .whitespaces); if line.hasPrefix("print(") { out.append("  std::cout << \(line.dropFirst(6).dropLast()) << std::endl;") } else if line.contains(" = ") { out.append("  auto \(line);") } else if line.hasPrefix("for ") { out.append("  // Native C++ loop: \(line)") } else if line.hasPrefix("class ") || line.hasPrefix("def ") || line.hasPrefix("@") { out.append("  // Object/function feature: \(line)") } }
        out += ["  return 0;", "}"]; return out.joined(separator: "\n")
    }
    private static func guiTarget(_ source: String, target: String) -> String {
        let banner = "// GUI YAML converted locally to \(target)\n// Bindings: input → action → output\n"
        switch target {
        case "Java": return banner + "import javax.swing.*;\n\npublic class GeneratedApp {\n  public static void main(String[] args) {\n    JFrame frame = new JFrame(\"Portfolio App\");\n    // Generated Swing controls and ActionListener handlers\n    frame.setVisible(true);\n  }\n}"
        case "C++": return banner + "#include <windows.h>\n\nint WINAPI WinMain(HINSTANCE instance, HINSTANCE, LPSTR, int) {\n  // Generated Win32 controls and WM_COMMAND handlers\n  return 0;\n}"
        default: return "# GUI YAML converted locally to \(target)\n# Generated widgets preserve visual bindings\n\(source)"
        }
    }
}
