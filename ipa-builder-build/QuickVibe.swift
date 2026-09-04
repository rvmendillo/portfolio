import SwiftUI

struct QuickVibeSheet: View {
    @EnvironmentObject private var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var planner = AppleScreenPlanner.shared

    @State private var prompt = ""
    @State private var isRunning = false
    @State private var status = "Describe the screen you want. ReyForge will choose and place the native controls."
    @State private var planSummary = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Intelligence") {
                    LabeledContent("Planner", value: "Apple Foundation Models")
                    LabeledContent("Storage", value: "System model · no extra download")
                    Label(planner.availabilityText, systemImage: planner.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(planner.isAvailable ? .green : .orange)
                }

                Section {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 130)
                        .overlay(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("Example: Create a dashboard for a personal finance app with useful KPIs, savings progress, recent transactions, and a primary add-transaction action.")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Label("Describe the screen", systemImage: "wand.and.stars")
                } footer: {
                    Text("The model generates a typed screen plan — component types, positions, sizes, hierarchy, and interactions. ReyForge applies that plan directly to the native SwiftUI canvas. It does not generate or parse Swift source code.")
                }

                Section("How it behaves") {
                    Label("Infers the right controls from broad requests", systemImage: "brain.head.profile")
                    Label("Places controls automatically on the 390×844 canvas", systemImage: "rectangle.3.group")
                    Label("Adds useful actions and navigation", systemImage: "arrow.triangle.branch")
                    Label("Keeps the result editable in Studio", systemImage: "slider.horizontal.3")
                }

                Section("Status") {
                    HStack {
                        if isRunning { ProgressView() }
                        Text(status)
                    }
                    if !planSummary.isEmpty {
                        Text(planSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        runVibe()
                    } label: {
                        Label(isRunning ? "Designing Screen…" : "Create / Modify Screen", systemImage: "sparkles.rectangle.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("AI Screen Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func runVibe() {
        guard let project = store.selected else { return }
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        isRunning = true
        planSummary = ""
        status = planner.isAvailable
            ? "Apple Intelligence is planning the native screen…"
            : planner.availabilityText

        Task {
            do {
                let plan = try await planner.plan(prompt: request, project: project)
                var inserted: [StudioComponent] = []
                store.updateProject { current in
                    inserted = planner.apply(plan, to: &current)
                }
                store.selectedComponentID = inserted.last?.id ?? store.selectedComponentID
                planSummary = "\(plan.summary) · \(inserted.count) native component(s) placed."
                status = "Screen updated live on the canvas."
            } catch {
                if request.lowercased().contains("dashboard") {
                    let fallback = AppleScreenPlanner.fallbackDashboard()
                    var inserted: [StudioComponent] = []
                    store.updateProject { current in
                        inserted = planner.apply(fallback, to: &current)
                    }
                    store.selectedComponentID = inserted.last?.id ?? store.selectedComponentID
                    planSummary = "Apple Intelligence was unavailable, so ReyForge used its native dashboard template."
                    status = "Dashboard placed. \(error.localizedDescription)"
                } else {
                    status = error.localizedDescription
                    planSummary = "No changes were applied."
                }
            }
            isRunning = false
        }
    }
}
