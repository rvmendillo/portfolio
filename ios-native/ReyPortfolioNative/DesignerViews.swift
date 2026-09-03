import SwiftUI

struct NativeDesignerView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var packages: NativePackageStore
    @State private var projectName = "Native Calculator"
    @State private var nodes: [DesignerNode] = []
    @State private var connections: [DesignerConnection] = []
    @State private var selectedID: UUID?
    @State private var connectionStart: UUID?
    @State private var connectMode = false
    @State private var showCode = false
    @State private var showPreview = false
    @State private var dragOrigins: [UUID: CGPoint] = [:]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            palette
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color(hex: "EAF0F6"))
                    Canvas { context, _ in
                        for connection in connections {
                            guard let from = nodes.first(where: { $0.id == connection.from }), let to = nodes.first(where: { $0.id == connection.to }) else { continue }
                            var path = Path(); path.move(to: CGPoint(x: from.x + 52, y: from.y)); path.addCurve(to: CGPoint(x: to.x - 52, y: to.y), control1: CGPoint(x: from.x + 95, y: from.y), control2: CGPoint(x: to.x - 95, y: to.y)); context.stroke(path, with: .color(theme.accent), lineWidth: 2)
                        }
                    }
                    ForEach(nodes) { node in
                        DesignerCanvasNode(node: node, selected: selectedID == node.id, connecting: connectionStart == node.id)
                            .position(x: node.x, y: node.y)
                            .onTapGesture { tapNode(node.id) }
                            .gesture(DragGesture().onChanged { value in move(node.id, translation: value.translation, size: proxy.size) }.onEnded { _ in dragOrigins[node.id] = nil; saveDraft() })
                    }
                    if nodes.isEmpty { VStack(spacing: 8) { Image(systemName: "square.on.square.dashed").font(.largeTitle); Text("Tap a component to begin").font(.subheadline.bold()) }.foregroundStyle(Color(hex: "53657A")) }
                }.padding(10)
            }
            .frame(minHeight: 245)
            inspector
        }
        .sheet(isPresented: $showCode) { NavigationStack { ScrollView([.horizontal, .vertical]) { Text(yaml).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding() }.navigationTitle("Generated GUI YAML").toolbar { ToolbarItem(placement: .navigationBarTrailing) { ShareLink(item: yaml) { Image(systemName: "square.and.arrow.up") } } } } }
        .sheet(isPresented: $showPreview) { NativePackagePreviewView(package: NativePackage(name: projectName, nodes: nodes, connections: connections)).environmentObject(theme).presentationDetents([.large]) }
        .onAppear(perform: loadDraft)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("Project name", text: $projectName).font(.subheadline.bold()).textFieldStyle(.roundedBorder)
            Button { loadDemo() } label: { Image(systemName: "sparkles") }.buttonStyle(.bordered)
            Button { showPreview = true } label: { Image(systemName: "play.fill") }.buttonStyle(.borderedProminent).tint(theme.accent)
            Menu { Button("Install in App Studio") { packages.install(name: projectName, nodes: nodes, connections: connections) }; Button("Clear canvas", role: .destructive) { nodes = []; connections = []; selectedID = nil; saveDraft() } } label: { Image(systemName: "ellipsis.circle") }
        }.padding(10).background(.ultraThinMaterial)
    }

    private var palette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(DesignerNodeKind.allCases) { kind in Button { add(kind) } label: { Label(kind.title, systemImage: kind.symbol).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 8).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(SpringButtonStyle()) }
                Divider().frame(height: 28)
                Button { connectMode.toggle(); connectionStart = nil } label: { Label(connectMode ? "Connecting" : "Connect", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.caption.bold()) }.buttonStyle(.borderedProminent).tint(connectMode ? .mint : theme.accent)
                Button { showCode = true } label: { Label("Code", systemImage: "chevron.left.forwardslash.chevron.right").font(.caption.bold()) }.buttonStyle(.bordered)
            }.padding(.horizontal, 10).padding(.vertical, 8)
        }
    }

    @ViewBuilder private var inspector: some View {
        if let index = nodes.firstIndex(where: { $0.id == selectedID }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    TextField("ID", text: $nodes[index].name).frame(width: 115).textFieldStyle(.roundedBorder)
                    TextField("Text", text: $nodes[index].text).frame(width: 150).textFieldStyle(.roundedBorder)
                    Picker("Action", selection: $nodes[index].operation) { ForEach(DesignerOperation.allCases) { Text($0.title).tag($0) } }.frame(width: 125)
                    if nodes[index].operation == .formula { TextField("input1 * (input2 + 3)", text: $nodes[index].formula).frame(width: 210).textFieldStyle(.roundedBorder) }
                    Button(role: .destructive) { delete(nodes[index].id) } label: { Label("Delete", systemImage: "trash") }.buttonStyle(.bordered)
                }.font(.caption).padding(10)
            }.background(.ultraThinMaterial).onChange(of: nodes) { _ in saveDraft() }
        } else {
            HStack { Text(connectMode ? "Tap a source, then a destination." : "Select a component to edit it.").font(.caption).foregroundStyle(theme.secondary); Spacer(); Text("\(connections.count) connections").font(.caption2).foregroundStyle(theme.secondary) }.padding(12).background(.ultraThinMaterial)
        }
    }

    private func add(_ kind: DesignerNodeKind) { let count = nodes.filter { $0.kind == kind }.count + 1; var node = DesignerNode(kind: kind, index: count); node.x = 90 + Double(nodes.count % 3) * 110; node.y = 60 + Double(nodes.count % 4) * 55; nodes.append(node); selectedID = node.id; saveDraft() }
    private func move(_ id: UUID, translation: CGSize, size: CGSize) { guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }; let origin = dragOrigins[id] ?? CGPoint(x: nodes[index].x, y: nodes[index].y); dragOrigins[id] = origin; nodes[index].x = min(max(58, origin.x + translation.width), max(58, size.width - 58)); nodes[index].y = min(max(28, origin.y + translation.height), max(28, size.height - 28)); selectedID = id }
    private func tapNode(_ id: UUID) { selectedID = id; guard connectMode else { return }; if let start = connectionStart { if start != id && !connections.contains(where: { $0.from == start && $0.to == id }) { connections.append(DesignerConnection(from: start, to: id)) }; connectionStart = nil; saveDraft() } else { connectionStart = id } }
    private func delete(_ id: UUID) { nodes.removeAll { $0.id == id }; connections.removeAll { $0.from == id || $0.to == id }; selectedID = nil; saveDraft() }
    private func loadDemo() {
        var first = DesignerNode(kind: .input, index: 1, x: 80, y: 65); first.text = "First number"
        var second = DesignerNode(kind: .input, index: 2, x: 80, y: 135); second.text = "Second number"
        var button = DesignerNode(kind: .button, index: 1, x: 230, y: 100); button.text = "Add"; button.operation = .add
        var output = DesignerNode(kind: .output, index: 1, x: 370, y: 100); output.text = "Result"
        nodes = [first, second, button, output]
        connections = [DesignerConnection(from: first.id, to: button.id), DesignerConnection(from: second.id, to: button.id), DesignerConnection(from: button.id, to: output.id)]
        selectedID = button.id; saveDraft()
    }
    private var yaml: String {
        var lines = ["app: \"\(projectName.prefix(48))\"", "components:"]
        for node in nodes { lines += ["  - id: \(node.name)", "    type: \(node.kind.rawValue)", "    text: \"\(node.text.replacingOccurrences(of: "\"", with: "'"))\"", "    x: \(Int(node.x))", "    y: \(Int(node.y))"]; if node.kind == .button { lines.append("    operation: \(node.operation.rawValue)"); if !node.formula.isEmpty { lines.append("    formula: \"\(node.formula)\"") } } }
        lines.append("connections:"); for connection in connections { if let from = nodes.first(where: { $0.id == connection.from }), let to = nodes.first(where: { $0.id == connection.to }) { lines += ["  - from: \(from.name)", "    to: \(to.name)"] } }
        return lines.joined(separator: "\n")
    }
    private func saveDraft() { let package = NativePackage(name: projectName, nodes: nodes, connections: connections); if let data = try? JSONEncoder().encode(package) { UserDefaults.standard.set(data, forKey: "native.designer.draft") } }
    private func loadDraft() { guard let data = UserDefaults.standard.data(forKey: "native.designer.draft"), let package = try? JSONDecoder().decode(NativePackage.self, from: data) else { loadDemo(); return }; projectName = package.name; nodes = package.nodes; connections = package.connections }
}

private struct DesignerCanvasNode: View {
    let node: DesignerNode; let selected: Bool; let connecting: Bool
    var body: some View {
        Group {
            switch node.kind {
            case .input: HStack { Text(node.text); Spacer(); Image(systemName: "pencil") }
            case .button: Text(node.text).fontWeight(.semibold)
            case .output: HStack { Image(systemName: "equal"); Text(node.text) }
            case .label: Text(node.text).fontWeight(.medium)
            }
        }
        .font(.caption).foregroundStyle(Color(hex: "172033")).padding(.horizontal, 10).frame(width: 112, height: 38)
        .background(node.kind == .button ? Color(hex: "CFE4FA") : .white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(connecting ? .orange : selected ? .blue : Color(hex: "A8B8C9"), lineWidth: selected || connecting ? 3 : 1))
        .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
    }
}

struct NativePackagePreviewView: View {
    @EnvironmentObject private var theme: ThemeStore
    let package: NativePackage
    @State private var fields: [UUID: String] = [:]
    @State private var outputs: [UUID: String] = [:]
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "app.fill").foregroundStyle(theme.accent); Text(package.name).font(.headline); Spacer(); Text("Native preview").font(.caption).foregroundStyle(theme.secondary) }.padding().background(.ultraThinMaterial)
            GeometryReader { proxy in ZStack { Color(hex: "EDF2F7"); ForEach(package.nodes) { node in previewNode(node).position(x: min(node.x, max(60, proxy.size.width - 60)), y: min(node.y, max(28, proxy.size.height - 28))) } } }
        }.foregroundStyle(theme.primary).background(theme.background)
    }
    @ViewBuilder private func previewNode(_ node: DesignerNode) -> some View {
        switch node.kind {
        case .input: TextField(node.text, text: Binding(get: { fields[node.id] ?? "" }, set: { fields[node.id] = String($0.prefix(200)) })).textFieldStyle(.roundedBorder).frame(width: 132)
        case .button: Button(node.text) { execute(node) }.buttonStyle(.borderedProminent).tint(theme.accent)
        case .output: Text(outputs[node.id] ?? node.text).font(.caption.bold()).foregroundStyle(Color(hex: "172033")).padding(9).frame(width: 132).background(.white, in: RoundedRectangle(cornerRadius: 8))
        case .label: Text(node.text).font(.caption.bold()).foregroundStyle(Color(hex: "172033")).frame(width: 132)
        }
    }
    private func execute(_ button: DesignerNode) {
        let incoming = package.connections.filter { $0.to == button.id }.compactMap { id in package.nodes.first(where: { $0.id == id.from }) }
        let outgoing = package.connections.filter { $0.from == button.id }.map(\.to)
        let values = incoming.map { fields[$0.id] ?? "" }; var result = ""
        switch button.operation {
        case .add: result = MathFormatter.string(values.reduce(0) { $0 + (Double($1) ?? 0) })
        case .subtract: result = MathFormatter.string(values.dropFirst().reduce(Double(values.first ?? "") ?? 0) { $0 - (Double($1) ?? 0) })
        case .multiply: result = MathFormatter.string(values.reduce(1) { $0 * (Double($1) ?? 1) })
        case .divide: var value = Double(values.first ?? "") ?? 0; for item in values.dropFirst() { let divisor = Double(item) ?? 0; if divisor == 0 { result = "Division by zero"; break }; value /= divisor }; if result.isEmpty { result = MathFormatter.string(value) }
        case .formula: var variables: [String: Double] = [:]; for (index, node) in incoming.enumerated() { let value = Double(fields[node.id] ?? "") ?? 0; variables[node.name] = value; variables["input\(index + 1)"] = value }; do { result = MathFormatter.string(try SafeMath.evaluate(button.formula, variables: variables)) } catch { result = error.localizedDescription }
        case .join: result = values.joined(separator: " ")
        case .uppercase: result = values.first?.uppercased() ?? ""
        case .lowercase: result = values.first?.lowercased() ?? ""
        case .clear: for node in incoming { fields[node.id] = "" }; result = ""
        case .none: result = values.joined(separator: " ")
        }
        for id in outgoing { outputs[id] = result }
    }
}

struct NativeAppStudioView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var store: NativePackageStore
    @State private var selected: NativePackage?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) { Image(systemName: "shippingbox.fill").font(.largeTitle).foregroundStyle(theme.accent); VStack(alignment: .leading) { Text("Native App Studio").font(.title2.bold()); Text("GUI Designer packages stored on this device").font(.caption).foregroundStyle(theme.secondary) } }.padding().nativeCard()
                Text("Installed by you").font(.headline)
                if store.packages.isEmpty { ContentUnavailableViewCompat(title: "No installed designs", symbol: "square.on.square.dashed", message: "Build and install one from GUI Designer.").frame(maxWidth: .infinity).padding().nativeCard() }
                ForEach(store.packages) { package in HStack { Image(systemName: "app.fill").frame(width: 42, height: 42).background(theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 11)); VStack(alignment: .leading) { Text(package.name).font(.subheadline.bold()); Text("\(package.nodes.count) components · \(package.connections.count) bindings").font(.caption).foregroundStyle(theme.secondary) }; Spacer(); Button("Open") { selected = package }.buttonStyle(.borderedProminent).tint(theme.accent); Button(role: .destructive) { store.remove(package) } label: { Image(systemName: "trash") } }.padding(12).nativeCard(corner: 15) }
            }.padding(16)
        }.sheet(item: $selected) { NativePackagePreviewView(package: $0).environmentObject(theme).presentationDetents([.large]) }
    }
}
