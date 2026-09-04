import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var audio: AudioController
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.22),
                        Color.purple.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        inputCard
                        presetSection
                        mixCard
                        renderButton
                        outputCard
                        privacyNote
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("VoxHarmony")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        audio.importAudio(from: url)
                    }
                case .failure(let error):
                    audio.errorMessage = error.localizedDescription
                }
            }
            .alert(
                "VoxHarmony",
                isPresented: Binding(
                    get: { audio.errorMessage != nil },
                    set: { newValue in
                        if !newValue { audio.errorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    audio.errorMessage = nil
                }
            } message: {
                Text(audio.errorMessage ?? "")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 62, height: 62)
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 28, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your voice, multiplied")
                        .font(.title2.bold())
                    Text("Record one lead vocal and turn it into layered harmonies made from the same performance.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 7) {
                Label("On-device", systemImage: "iphone.gen3")
                Text("•")
                    .foregroundStyle(.tertiary)
                Label("M4A export", systemImage: "square.and.arrow.up")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("1. Add your vocal", icon: "mic.fill")

            HStack(spacing: 12) {
                Button {
                    audio.toggleRecording()
                } label: {
                    Label(audio.isRecording ? "Stop" : "Record", systemImage: audio.isRecording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(audio.isRecording ? .red : .indigo)
                .disabled(audio.isProcessing)

                Button {
                    showImporter = true
                } label: {
                    Label("Import", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(audio.isRecording || audio.isProcessing)
            }

            HStack(spacing: 12) {
                Image(systemName: audio.sourceURL == nil ? "waveform.slash" : "waveform")
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(audio.sourceURL == nil ? .secondary : .primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(audio.sourceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(audio.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                if audio.sourceURL != nil {
                    Button {
                        audio.playSource()
                    } label: {
                        Image(systemName: audio.isPlaying ? "stop.fill" : "play.fill")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .disabled(audio.isRecording || audio.isProcessing)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Best results come from a clean, isolated singing track. Use headphones while recording so the instrumental does not leak into the microphone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("2. Choose a harmony", icon: "music.note.list")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(HarmonyPreset.presets) { preset in
                        Button {
                            withAnimation(.snappy) {
                                audio.selectedPreset = preset
                                audio.outputURL = nil
                                audio.outputName = ""
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Image(systemName: preset.symbol)
                                        .font(.title3)
                                    Spacer()
                                    if audio.selectedPreset.id == preset.id {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                Text(preset.name)
                                    .font(.subheadline.bold())
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            .frame(width: 170, height: 116, alignment: .topLeading)
                            .padding(14)
                            .background(
                                audio.selectedPreset.id == preset.id ? Color.indigo.opacity(0.16) : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(audio.selectedPreset.id == preset.id ? Color.indigo.opacity(0.55) : Color.clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var mixCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("3. Balance the stack", icon: "slider.horizontal.3")

            levelSlider(
                title: "Lead",
                subtitle: "Original vocal",
                value: $audio.leadLevel,
                range: 0.25...1.0
            )

            levelSlider(
                title: "Harmony",
                subtitle: "Generated vocal layers",
                value: $audio.harmonyLevel,
                range: 0.15...1.0
            )
        }
        .cardStyle()
    }

    private var renderButton: some View {
        Button {
            audio.renderHarmony()
        } label: {
            HStack(spacing: 10) {
                if audio.isProcessing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(audio.isProcessing ? "Creating Harmony…" : "Create Harmonized Version")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.indigo)
        .disabled(audio.sourceURL == nil || audio.isRecording || audio.isProcessing)
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("4. Result", icon: "waveform.badge.plus")

            if let outputURL = audio.outputURL {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.indigo.opacity(0.14))
                            .frame(width: 50, height: 50)
                        Image(systemName: "music.note")
                            .font(.title3.bold())
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(audio.selectedPreset.name)
                            .font(.headline)
                        Text(audio.outputName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        audio.playOutput()
                    } label: {
                        Label(audio.isPlaying ? "Stop" : "Preview", systemImage: audio.isPlaying ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: outputURL) {
                        Label("Share M4A", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
            } else {
                ContentUnavailableView(
                    "No harmony yet",
                    systemImage: "waveform",
                    description: Text("Your rendered vocal stack will appear here.")
                )
                .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
    }

    private var privacyNote: some View {
        Label(
            "Your recording stays on this iPhone during processing. VoxHarmony does not require an account or upload your voice to a server.",
            systemImage: "lock.shield.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 20)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func levelSlider(
        title: String,
        subtitle: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(.indigo)
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
