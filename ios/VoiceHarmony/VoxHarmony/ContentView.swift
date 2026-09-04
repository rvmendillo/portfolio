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
                        Color.indigo.opacity(0.28),
                        Color.purple.opacity(0.16),
                        Color.black.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        inputCard
                        analysisCard
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("VOXHARMONY STUDIO")
                        .font(.caption2.bold())
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                    Text("Your voice. Your harmony language.")
                        .font(.title2.bold())
                    Text("Adaptive pop, solfège, pentatonic and jazz vocal arranging from one sung melody.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 7) {
                Label("Auto key + scale", systemImage: "music.note")
                Text("•").foregroundStyle(.tertiary)
                Label("Chord inference", systemImage: "square.stack.3d.up")
                Text("•").foregroundStyle(.tertiary)
                Label("On-device", systemImage: "iphone.gen3")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text("by Rey")
                .font(.caption2.bold())
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.indigo.opacity(0.13), in: Capsule())
                .padding(12)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("1. Add your lead vocal", icon: "mic.fill")

            HStack(spacing: 12) {
                Button {
                    audio.toggleRecording()
                } label: {
                    Label(audio.isRecording ? "Stop" : "Record", systemImage: audio.isRecording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(audio.isRecording ? .red : .indigo)
                .disabled(audio.isProcessing || audio.isAnalyzing)

                Button {
                    showImporter = true
                } label: {
                    Label("Import", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(audio.isRecording || audio.isProcessing || audio.isAnalyzing)
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
                        .lineLimit(3)
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
                    .disabled(audio.isRecording || audio.isProcessing || audio.isAnalyzing)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("For melody-only chord inference, isolated vocals work best. If the melody is ambiguous, the chord labels are musical suggestions rather than guaranteed original chords.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("2. Musical analysis", icon: "waveform.path.ecg")

            if audio.isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listening to your melody…")
                            .font(.subheadline.bold())
                        Text("Estimating pitch classes, key, scale and likely harmony movement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let analysis = audio.analysis {
                HStack(spacing: 10) {
                    metricPill(
                        title: "KEY / SCALE",
                        value: analysis.key.displayName,
                        symbol: "key.fill"
                    )
                    metricPill(
                        title: "CONFIDENCE",
                        value: "\(Int((analysis.key.confidence * 100).rounded()))%",
                        symbol: "checkmark.seal.fill"
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Likely chord path from melody")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if analysis.chords.isEmpty {
                        Text("No chord path estimated")
                            .font(.subheadline)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(Array(analysis.chords.prefix(10).enumerated()), id: \.offset) { _, chord in
                                    Text(chord.name)
                                        .font(.subheadline.monospaced().bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Color.purple.opacity(0.10), in: Capsule())
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Waiting for a vocal",
                    systemImage: "music.note",
                    description: Text("Key, scale and chord suggestions appear automatically after recording or importing.")
                )
                .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("3. Choose a harmony language", icon: "music.note.list")

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
                                    .lineLimit(3)
                            }
                            .frame(width: 184, height: 126, alignment: .topLeading)
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

            if audio.selectedPreset.id == "pop-pentatonic" {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Signature mapping", systemImage: "sparkle")
                        .font(.caption.bold())
                    Text("In a C-major context, mi–re–do can map to sol–fa–mi above while the pentatonic lower voice maps to do–la–sol.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(11)
                .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .cardStyle()
    }

    private var mixCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("4. Balance the stack", icon: "slider.horizontal.3")

            levelSlider(
                title: "Lead",
                subtitle: "Original vocal",
                value: $audio.leadLevel,
                range: 0.25...1.0
            )

            levelSlider(
                title: "Harmony",
                subtitle: "Adaptive generated voices",
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
                Text(audio.isProcessing ? "Arranging Your Voices…" : "Create Adaptive Harmony")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.indigo)
        .disabled(audio.sourceURL == nil || audio.analysis == nil || audio.isRecording || audio.isProcessing || audio.isAnalyzing)
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("5. Result", icon: "waveform.badge.plus")

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
                        if let analysis = audio.analysis {
                            Text("\(analysis.key.displayName) • adaptive")
                                .font(.caption.bold())
                                .foregroundStyle(.indigo)
                        }
                        Text(audio.outputName)
                            .font(.caption2)
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
                    description: Text("Your key-aware rendered vocal stack will appear here.")
                )
                .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
    }

    private var privacyNote: some View {
        Label(
            "Pitch, key, scale, chord inference and harmony rendering stay on this iPhone. VoxHarmony does not require an account or upload your voice to a server.",
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

    private func metricPill(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
