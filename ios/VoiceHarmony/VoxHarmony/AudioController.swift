import Foundation
import AVFoundation
import Combine

final class AudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var sourceURL: URL?
    @Published var outputURL: URL?
    @Published var sourceName: String = "No vocal selected"
    @Published var outputName: String = ""
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isAnalyzing = false
    @Published var isPlaying = false
    @Published var statusText = "Record or import an isolated vocal to begin."
    @Published var errorMessage: String?
    @Published var selectedPreset: HarmonyPreset = HarmonyPreset.presets[0]
    @Published var leadLevel: Double = 0.88
    @Published var harmonyLevel: Double = 0.72
    @Published var analysis: MusicalAnalysis?
    @Published var analysisEngineName: String = "Basic Pitch AI"

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    let workspaceDirectory: URL

    override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent("VoxHarmony", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.workspaceDirectory = directory
        super.init()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.startRecording()
                } else {
                    self.errorMessage = "Microphone access is required to record a vocal. You can still import an audio file."
                }
            }
        }
    }

    private func startRecording() {
        do {
            stopPlayback()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let url = workspaceDirectory.appendingPathComponent("Vocal-\(formatter.string(from: Date())).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 192_000
            ]

            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            newRecorder.prepareToRecord()
            guard newRecorder.record() else {
                throw AudioControllerError.recordingCouldNotStart
            }

            recorder = newRecorder
            isRecording = true
            analysis = nil
            outputURL = nil
            outputName = ""
            statusText = "Recording… sing the lead vocal, then tap Stop."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        sourceURL = recorder.url
        sourceName = recorder.url.lastPathComponent
        outputURL = nil
        outputName = ""
        analysis = nil
        beginAnalysis(for: recorder.url)
    }

    func importAudio(from url: URL) {
        stopPlayback()
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let destination = workspaceDirectory.appendingPathComponent("Imported-\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)

            _ = try AVAudioFile(forReading: destination)
            sourceURL = destination
            sourceName = url.lastPathComponent
            outputURL = nil
            outputName = ""
            analysis = nil
            beginAnalysis(for: destination)
        } catch {
            errorMessage = "That audio file could not be imported: \(error.localizedDescription)"
        }
    }

    private func beginAnalysis(for url: URL) {
        isAnalyzing = true
        statusText = "Basic Pitch AI is transcribing melody and inferring key, scale and chords…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let resolved = try Self.resolveAnalysis(for: url)
                DispatchQueue.main.async {
                    guard let self, self.sourceURL == url else { return }
                    self.analysis = resolved.analysis
                    self.analysisEngineName = resolved.engineName
                    self.isAnalyzing = false
                    let percent = Int((resolved.analysis.key.confidence * 100).rounded())
                    self.statusText = "\(resolved.engineName) • \(resolved.analysis.key.displayName) • \(percent)% key confidence • \(resolved.analysis.chords.count) chord windows"
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.sourceURL == url else { return }
                    self.isAnalyzing = false
                    self.statusText = "Melody analysis needs a cleaner vocal."
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static func resolveAnalysis(for url: URL) throws -> (analysis: MusicalAnalysis, engineName: String) {
        do {
            return (try MLPitchAssistant.analyze(sourceURL: url), "Basic Pitch AI")
        } catch {
            // Keep VoxHarmony usable if the ML model cannot run on a particular file/device.
            return (try MelodyAnalyzer.analyze(sourceURL: url), "Adaptive pitch fallback")
        }
    }

    func playSource() {
        play(url: sourceURL)
    }

    func playOutput() {
        play(url: outputURL)
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func play(url: URL?) {
        guard let url else { return }
        do {
            if isPlaying {
                stopPlayback()
                return
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                throw AudioControllerError.playbackCouldNotStart
            }
            player = newPlayer
            isPlaying = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renderHarmony() {
        guard let sourceURL else {
            errorMessage = "Record or import a vocal first."
            return
        }
        guard !isRecording else {
            errorMessage = "Stop the recording before creating harmony."
            return
        }
        guard !isAnalyzing else {
            errorMessage = "VoxHarmony is still detecting the melody and key."
            return
        }

        stopPlayback()
        isProcessing = true
        statusText = "Creating \(selectedPreset.name) from AI-transcribed melody, key and chord context…"

        let preset = selectedPreset
        let lead = Float(leadLevel)
        let harmony = Float(harmonyLevel)
        let destinationDirectory = workspaceDirectory
        let existingAnalysis = analysis
        let existingEngineName = analysisEngineName

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let resolved: (analysis: MusicalAnalysis, engineName: String)
                if let existingAnalysis {
                    resolved = (existingAnalysis, existingEngineName)
                } else {
                    resolved = try Self.resolveAnalysis(for: sourceURL)
                }

                let result = try HarmonyRenderer.render(
                    sourceURL: sourceURL,
                    preset: preset,
                    analysis: resolved.analysis,
                    leadLevel: lead,
                    harmonyLevel: harmony,
                    destinationDirectory: destinationDirectory
                )
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.analysis = resolved.analysis
                    self.analysisEngineName = resolved.engineName
                    self.outputURL = result
                    self.outputName = result.lastPathComponent
                    self.isProcessing = false
                    self.statusText = "Harmony ready in \(resolved.analysis.key.displayName) using \(resolved.engineName). Preview it or share the finished file."
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isProcessing = false
                    self.statusText = "Could not render the adaptive harmony."
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.player = nil
        }
    }
}

enum AudioControllerError: LocalizedError {
    case recordingCouldNotStart
    case playbackCouldNotStart

    var errorDescription: String? {
        switch self {
        case .recordingCouldNotStart:
            return "The microphone recording could not start."
        case .playbackCouldNotStart:
            return "Audio playback could not start."
        }
    }
}
