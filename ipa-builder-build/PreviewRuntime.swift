import SwiftUI
import UIKit

struct StudioLivePreview: View {
    let project: StudioProject
    @Environment(\.dismiss) private var dismiss
    @State private var variables: [String: String]
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var route = ""
    @State private var showWidgetPreview = false

    init(project: StudioProject) {
        self.project = project
        _variables = State(initialValue: project.variables)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let scale = min(1.0, max(0.45, min((proxy.size.width - 24) / 390, (proxy.size.height - 24) / 844)))
                ZStack {
                    Color(uiColor: .secondarySystemGroupedBackground).ignoresSafeArea()
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 46, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                            .frame(width: 390, height: 844)
                        VStack {
                            Capsule().fill(.primary.opacity(0.82)).frame(width: 104, height: 28).padding(.top, 8)
                            Spacer()
                        }
                        .frame(width: 390, height: 844)
                        .allowsHitTesting(false)
                        ForEach(project.components) { component in
                            PreviewComponent(component: component, variables: $variables, runActions: { run($0) })
                                .frame(width: component.width, height: component.height)
                                .position(x: component.x, y: component.y)
                        }
                    }
                    .frame(width: 390, height: 844)
                    .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 46, style: .continuous).stroke(.primary.opacity(0.15), lineWidth: 2) }
                    .shadow(radius: 20, y: 10)
                    .scaleEffect(scale)
                }
            }
            .navigationTitle(route.isEmpty ? "Preview · \(project.name)" : "Preview · \(route)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                if project.widget.enabled {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showWidgetPreview = true } label: { Image(systemName: "square.grid.2x2") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(variables.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: variables[key] ?? "")
                        }
                    } label: { Image(systemName: "curlybraces") }
                }
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage) }
        .sheet(isPresented: $showWidgetPreview) {
            WidgetPreviewCard(config: project.widget).presentationDetents([.medium])
        }
    }

    private func run(_ actions: [StudioAction]) {
        for action in actions {
            switch action.kind {
            case .showAlert:
                alertTitle = action.key.isEmpty ? "ReyForge" : action.key
                alertMessage = interpolate(action.value)
                showAlert = true
            case .navigate:
                route = action.value.isEmpty ? action.key : action.value
            case .setVariable:
                variables[action.key] = interpolate(action.value)
            case .toggleVariable:
                let current = (variables[action.key] ?? "false").lowercased() == "true"
                variables[action.key] = String(!current)
            case .increment:
                let current = Int(variables[action.key] ?? "0") ?? 0
                variables[action.key] = String(current + (Int(action.value) ?? 1))
            case .decrement:
                let current = Int(variables[action.key] ?? "0") ?? 0
                variables[action.key] = String(current - (Int(action.value) ?? 1))
            case .openURL:
                if let url = URL(string: interpolate(action.value)) { UIApplication.shared.open(url) }
            case .saveLocal:
                UserDefaults.standard.set(interpolate(action.value), forKey: "reyforge.preview.\(action.key)")
            case .apiGET:
                guard let url = URL(string: interpolate(action.value)) else { continue }
                Task {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        let key = action.key.isEmpty ? "response" : action.key
                        variables[key] = String(data: data.prefix(500), encoding: .utf8) ?? "HTTP \(code)"
                        alertTitle = "GET \(code)"
                        alertMessage = "Response stored in \(key)."
                        showAlert = true
                    } catch {
                        alertTitle = "Request failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            case .copyText:
                UIPasteboard.general.string = interpolate(action.value)
            }
        }
    }

    private func interpolate(_ value: String) -> String {
        var result = value
        for (key, variable) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: variable)
        }
        return result
    }
}

private struct PreviewComponent: View {
    let component: StudioComponent
    @Binding var variables: [String: String]
    let runActions: ([StudioAction]) -> Void

    var body: some View {
        switch component.kind {
        case .button:
            Button { runActions(component.actions) } label: {
                Text(component.text)
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: component.cornerRadius))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        case .link, .navigationLink:
            Button {
                if component.actions.isEmpty, component.kind == .link, let url = URL(string: component.detail) {
                    UIApplication.shared.open(url)
                } else {
                    runActions(component.actions)
                }
            } label: {
                HStack {
                    Image(systemName: component.kind == .link ? "link" : "chevron.right")
                    Text(component.text)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .foregroundStyle(.indigo)
            }
            .buttonStyle(.plain)
        case .shareLink:
            ShareLink(item: component.detail.isEmpty ? component.text : component.detail) {
                Label(component.text, systemImage: "square.and.arrow.up")
                    .padding(8)
                    .background(.quaternary, in: Capsule())
            }
        default:
            StudioComponentRenderer(component: component)
                .contentShape(Rectangle())
                .onTapGesture { if !component.actions.isEmpty { runActions(component.actions) } }
        }
    }
}

private struct WidgetPreviewCard: View {
    let config: StudioWidgetConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: config.symbol.isEmpty ? "sparkles" : config.symbol)
                        .font(.largeTitle)
                        .foregroundStyle(.indigo)
                    Text(config.title).font(.title3.bold())
                    Text(config.subtitle).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(18)
                .frame(width: config.family == "systemSmall" ? 170 : 330,
                       height: config.family == "systemLarge" ? 330 : 170,
                       alignment: .topLeading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                Text(config.family).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Widget Preview")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
