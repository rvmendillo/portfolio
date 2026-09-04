import SwiftUI

struct QuickVibeSheet: View {
    @EnvironmentObject private var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var modelManager = LargeCodeModelManager.shared

    @State private var prompt = ""
    @State private var isRunning = false
    @State private var status = "Describe a native iOS feature and ReyForge will add it directly."
    @State private var lastOutput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Local coding model") {
                    LabeledContent("Model", value: "Qwen2.5-Coder-3B")
                    LabeledContent("Quantization", value: "Q4_K_M")
                    LabeledContent("Storage", value: modelManager.sizeText)

                    HStack {
                        if modelManager.isDownloading { ProgressView() }
                        Text(modelManager.status)
                            .font(.caption)
                    }

                    if let error = modelManager.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if modelManager.isInstalled {
                        Button(role: .destructive) {
                            modelManager.removeModel()
                        } label: {
                            Label("Remove 3B Model", systemImage: "trash")
                        }
                    } else {
                        Button {
                            Task { await modelManager.downloadModel() }
                        } label: {
                            Label(modelManager.isDownloading ? "Downloading Model…" : "Download 3B Swift Coding Model", systemImage: "arrow.down.circle")
                        }
                        .disabled(modelManager.isDownloading)
                    }
                }

                Section {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("Example: Build a native iOS settings screen with account information, notification and Face ID toggles, a destructive sign-out button, and a medium WidgetKit summary.")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Label("Vibe request", systemImage: "sparkles")
                } footer: {
                    Text("Qwen2.5-Coder-3B-Instruct is code-specialized and runs locally through llama.cpp after a one-time ~2.1 GB download. ReyForge prompts it as a Swift 6 / SwiftUI / UIKit engineer. The deterministic fallback remains available if the model is not installed or inference fails.")
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
                        Label(isRunning ? "Building…" : "Build Native Feature", systemImage: "wand.and.stars")
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
        status = modelManager.isInstalled
            ? "Qwen2.5-Coder-3B is designing the native iOS feature…"
            : "3B model not installed — using deterministic fallback…"
        lastOutput = ""

        Task {
            let output: String
            var inferenceError: String?
            do {
                output = try await Task.detached(priority: .userInitiated) {
                    try LocalVibeModel.shared.propose(prompt: request, project: project)
                }.value
            } catch {
                output = ""
                inferenceError = error.localizedDescription
            }

            let patch = VibePatchParser.parse(output, fallbackPrompt: request, project: project)
            store.updateProject { current in
                current.components.append(contentsOf: patch.components)
                for (key, value) in patch.variableUpdates { current.variables[key] = value }
                if let widget = patch.widget { current.widget = widget }
            }
            store.selectedComponentID = patch.components.last?.id ?? store.selectedComponentID
            if output.isEmpty {
                lastOutput = inferenceError.map { "Fallback used: \($0)" } ?? "Deterministic fallback"
            } else {
                lastOutput = output
            }
            status = "Added \(patch.components.count) component(s). Changes are live on the canvas."
            isRunning = false
        }
    }
}
