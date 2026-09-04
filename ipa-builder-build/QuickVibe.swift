import SwiftUI

struct QuickVibeSheet: View {
    @EnvironmentObject private var store: StudioStore
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var isRunning = false
    @State private var status = "Describe a feature and ReyForge will add it directly."
    @State private var lastOutput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("Example: Add a settings card with notification and Face ID toggles, a Save button that shows an alert, and a medium widget.")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Label("Vibe request", systemImage: "sparkles")
                } footer: {
                    Text("SmolLM2-135M runs locally. Common UI requests use a deterministic fast path so feature insertion still works even if local inference fails.")
                }

                Section("Status") {
                    HStack {
                        if isRunning { ProgressView() }
                        Text(status)
                    }
                    if !lastOutput.isEmpty {
                        DisclosureGroup("Generated patch") {
                            Text(lastOutput)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button {
                        runVibe()
                    } label: {
                        Label(isRunning ? "Building…" : "Build Feature", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("ReyForge Vibe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func runVibe() {
        guard let project = store.selected else { return }
        let request = prompt
        isRunning = true
        status = "Building locally…"
        lastOutput = ""

        Task {
            let output: String
            do {
                output = try await Task.detached(priority: .userInitiated) {
                    try LocalVibeModel.shared.propose(prompt: request, project: project)
                }.value
            } catch {
                output = ""
            }

            let patch = VibePatchParser.parse(output, fallbackPrompt: request, project: project)
            store.updateProject { current in
                current.components.append(contentsOf: patch.components)
                for (key, value) in patch.variableUpdates { current.variables[key] = value }
                if let widget = patch.widget { current.widget = widget }
            }
            store.selectedComponentID = patch.components.last?.id ?? store.selectedComponentID
            lastOutput = output.isEmpty ? "Offline deterministic fallback" : output
            status = "Added \(patch.components.count) component(s). Changes are live on the canvas."
            isRunning = false
        }
    }
}
