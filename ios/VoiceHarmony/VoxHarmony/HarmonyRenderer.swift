import Foundation
import AVFoundation

struct HarmonyRenderer {
    static func render(
        sourceURL: URL,
        preset: HarmonyPreset,
        leadLevel: Float,
        harmonyLevel: Float,
        destinationDirectory: URL
    ) throws -> URL {
        let probe = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = probe.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw HarmonyRendererError.invalidAudioFormat
        }

        let renderChannels: AVAudioChannelCount = 2
        guard let renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: sourceFormat.sampleRate,
            channels: renderChannels
        ) else {
            throw HarmonyRendererError.invalidAudioFormat
        }

        let engine = AVAudioEngine()
        let submix = AVAudioMixerNode()
        engine.attach(submix)
        engine.connect(submix, to: engine.mainMixerNode, format: renderFormat)
        engine.mainMixerNode.outputVolume = 0.72

        var players: [AVAudioPlayerNode] = []
        var pitchUnits: [AVAudioUnitTimePitch] = []
        var files: [AVAudioFile] = []

        let dryFile = try AVAudioFile(forReading: sourceURL)
        let dryPlayer = AVAudioPlayerNode()
        engine.attach(dryPlayer)
        dryPlayer.volume = clamp(leadLevel, minimum: 0, maximum: 1)
        dryPlayer.pan = 0
        engine.connect(dryPlayer, to: submix, format: sourceFormat)
        dryPlayer.scheduleFile(dryFile, at: nil)
        players.append(dryPlayer)
        files.append(dryFile)

        for layer in preset.layers {
            let file = try AVAudioFile(forReading: sourceURL)
            let player = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch()

            timePitch.pitch = Float(layer.semitones * 100.0)
            timePitch.rate = 1.0
            timePitch.overlap = 8.0

            engine.attach(player)
            engine.attach(timePitch)

            player.volume = clamp(layer.gain * harmonyLevel, minimum: 0, maximum: 1)
            player.pan = clamp(layer.pan, minimum: -1, maximum: 1)

            engine.connect(player, to: timePitch, format: sourceFormat)
            engine.connect(timePitch, to: submix, format: sourceFormat)
            player.scheduleFile(file, at: nil)

            players.append(player)
            pitchUnits.append(timePitch)
            files.append(file)
        }

        let maxFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: maxFrames)
        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maxFrames
        ) else {
            throw HarmonyRendererError.couldNotCreateRenderBuffer
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let outputURL = destinationDirectory.appendingPathComponent(
            "VoxHarmony-\(preset.id)-\(formatter.string(from: Date())).m4a"
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: renderFormat.sampleRate,
            AVNumberOfChannelsKey: Int(renderFormat.channelCount),
            AVEncoderBitRateKey: 256_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        engine.prepare()
        try engine.start()
        players.forEach { $0.play() }

        let tailFrames: AVAudioFramePosition = 8_192
        let totalFrames = max(1, probe.length + tailFrames)
        var stalledPasses = 0

        while engine.manualRenderingSampleTime < totalFrames {
            let remaining = totalFrames - engine.manualRenderingSampleTime
            let requested = AVAudioFrameCount(min(AVAudioFramePosition(maxFrames), remaining))
            if requested == 0 { break }

            renderBuffer.frameLength = 0
            let status = try engine.renderOffline(requested, to: renderBuffer)

            switch status {
            case .success:
                stalledPasses = 0
                if renderBuffer.frameLength > 0 {
                    try outputFile.write(from: renderBuffer)
                }
            case .insufficientDataFromInputNode:
                if renderBuffer.frameLength > 0 {
                    try outputFile.write(from: renderBuffer)
                    stalledPasses = 0
                } else {
                    stalledPasses += 1
                    if stalledPasses >= 8 { break }
                }
            case .cannotDoInCurrentContext:
                stalledPasses += 1
                if stalledPasses >= 32 {
                    throw HarmonyRendererError.renderingStalled
                }
            case .error:
                throw HarmonyRendererError.renderingFailed
            @unknown default:
                throw HarmonyRendererError.renderingFailed
            }
        }

        players.forEach { $0.stop() }
        engine.stop()
        engine.disableManualRenderingMode()

        if !FileManager.default.fileExists(atPath: outputURL.path) {
            throw HarmonyRendererError.outputWasNotCreated
        }
        return outputURL
    }

    private static func clamp(_ value: Float, minimum: Float, maximum: Float) -> Float {
        min(maximum, max(minimum, value))
    }
}

enum HarmonyRendererError: LocalizedError {
    case invalidAudioFormat
    case couldNotCreateRenderBuffer
    case renderingStalled
    case renderingFailed
    case outputWasNotCreated

    var errorDescription: String? {
        switch self {
        case .invalidAudioFormat:
            return "The selected audio file has an unsupported format. Try an isolated WAV, M4A, AAC, or MP3 vocal."
        case .couldNotCreateRenderBuffer:
            return "VoxHarmony could not allocate its offline render buffer."
        case .renderingStalled:
            return "The audio engine stalled while rendering the harmony."
        case .renderingFailed:
            return "The audio engine could not finish the harmony render."
        case .outputWasNotCreated:
            return "The harmony render finished without producing an output file."
        }
    }
}
