import Foundation
import AVFoundation
import CoreML

/// On-device ML melody transcription using Spotify Basic Pitch.
/// The model is bundled at build time from spotify/basic-pitch (Apache-2.0).
struct MLPitchAssistant {
    private static let sampleRate = 22_050.0
    private static let inputSamples = 43_844
    private static let outputFrames = 172
    private static let noteBins = 88
    private static let midiOffset = 21
    private static let hopSamples = 256
    private static let overlapFrames = 15

    static func analyze(sourceURL: URL) throws -> MusicalAnalysis {
        let model = try loadModel()
        let samples = try loadMonoAudio(sourceURL)
        guard !samples.isEmpty else { throw MLPitchAssistantError.noAudio }

        let windows = makeWindows(samples)
        var pitchFrames: [PitchFrame] = []
        var chroma = Array(repeating: 0.0, count: 12)

        for (windowIndex, window) in windows.enumerated() {
            let input = try MLMultiArray(shape: [1, NSNumber(value: inputSamples), 1], dataType: .float32)
            let strides = input.strides.map { $0.intValue }
            let pointer = input.dataPointer.bindMemory(to: Float.self, capacity: input.count)
            for i in 0..<inputSamples {
                pointer[i * strides[1]] = window[i]
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_2": MLFeatureValue(multiArray: input)
            ])
            let prediction = try model.prediction(from: provider)
            guard
                let noteArray = prediction.featureValue(for: "Identity_1")?.multiArrayValue,
                let onsetArray = prediction.featureValue(for: "Identity_2")?.multiArrayValue
            else {
                throw MLPitchAssistantError.invalidModelOutput
            }

            let notes = read2D(noteArray, rows: outputFrames, cols: noteBins)
            let onsets = read2D(onsetArray, rows: outputFrames, cols: noteBins)

            let firstFrame = windowIndex == 0 ? 0 : overlapFrames
            let lastFrame = windowIndex == windows.count - 1 ? outputFrames : outputFrames - overlapFrames
            let windowStart = Double(windowIndex * windowHopSamples) / sampleRate

            for frameIndex in firstFrame..<lastFrame {
                var bestBin = 0
                var bestScore: Float = 0
                for bin in 0..<noteBins {
                    let score = notes[frameIndex][bin] * 0.82 + onsets[frameIndex][bin] * 0.18
                    if score > bestScore {
                        bestScore = score
                        bestBin = bin
                    }
                }

                let localTime = Double(frameIndex * hopSamples) / sampleRate
                let absoluteTime = max(0, windowStart + localTime)
                let confidence = Double(bestScore)
                let midi = bestScore >= 0.30 ? midiOffset + bestBin : nil
                pitchFrames.append(PitchFrame(time: absoluteTime, midiNote: midi, confidence: confidence))

                if let midi, bestScore >= 0.38 {
                    let pc = MusicTheory.positiveMod(midi, 12)
                    chroma[pc] += Double(bestScore) * (1.0 + Double(onsets[frameIndex][bestBin]) * 0.35)
                }
            }
        }

        let duration = Double(samples.count) / sampleRate
        guard pitchFrames.contains(where: { $0.midiNote != nil }) else {
            throw MLPitchAssistantError.noStablePitch
        }

        let key = estimateKey(chroma)
        let chords = inferChords(frames: pitchFrames, duration: duration, key: key)
        return MusicalAnalysis(key: key, frames: pitchFrames.sorted { $0.time < $1.time }, chords: chords)
    }

    private static var windowHopSamples: Int {
        inputSamples - (30 * hopSamples)
    }

    private static func loadModel() throws -> MLModel {
        let config = MLModelConfiguration()
        config.computeUnits = .all

        let names = ["nmp", "BasicPitch_nmp"]
        for name in names {
            if let compiled = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                return try MLModel(contentsOf: compiled, configuration: config)
            }
            if let package = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                let compiled = try MLModel.compileModel(at: package)
                return try MLModel(contentsOf: compiled, configuration: config)
            }
        }
        throw MLPitchAssistantError.modelMissing
    }

    private static func loadMonoAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw MLPitchAssistantError.audioConversionFailed
        }

        let estimatedFrames = AVAudioFrameCount(
            Double(file.length) * sampleRate / file.processingFormat.sampleRate
        ) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
            throw MLPitchAssistantError.audioConversionFailed
        }

        let inputFormat = file.processingFormat
        let inputBlock: AVAudioConverterInputBlock = { requestedFrames, status in
            let capacity = max(1, requestedFrames)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: capacity) else {
                status.pointee = .noDataNow
                return nil
            }
            do {
                try file.read(into: buffer, frameCount: capacity)
                if buffer.frameLength == 0 {
                    status.pointee = .endOfStream
                    return nil
                }
                status.pointee = .haveData
                return buffer
            } catch {
                status.pointee = .endOfStream
                return nil
            }
        }

        var error: NSError?
        converter.convert(to: output, error: &error, withInputFrom: inputBlock)
        if let error { throw error }
        guard let data = output.floatChannelData?[0] else {
            throw MLPitchAssistantError.audioConversionFailed
        }

        var samples = Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        if peak > 0.0001 {
            let scale = Float(0.98) / peak
            for index in samples.indices { samples[index] *= scale }
        }
        return samples
    }

    private static func makeWindows(_ samples: [Float]) -> [[Float]] {
        let overlap = 30 * hopSamples
        var padded = [Float](repeating: 0, count: overlap / 2)
        padded.append(contentsOf: samples)
        var result: [[Float]] = []
        var offset = 0
        while offset < padded.count {
            let end = min(offset + inputSamples, padded.count)
            var window = Array(padded[offset..<end])
            if window.count < inputSamples {
                window.append(contentsOf: repeatElement(Float(0), count: inputSamples - window.count))
            }
            result.append(window)
            offset += windowHopSamples
        }
        return result
    }

    private static func read2D(_ array: MLMultiArray, rows: Int, cols: Int) -> [[Float]] {
        let strides = array.strides.map { $0.intValue }
        let rowStride = strides.count >= 3 ? strides[1] : cols
        let colStride = strides.count >= 3 ? strides[2] : 1
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        var matrix = Array(repeating: Array(repeating: Float(0), count: cols), count: rows)
        for row in 0..<rows {
            for col in 0..<cols {
                matrix[row][col] = pointer[row * rowStride + col * colStride]
            }
        }
        return matrix
    }

    private static func estimateKey(_ chroma: [Double]) -> KeyEstimate {
        let total = max(0.0001, chroma.reduce(0, +))
        var candidates: [(Int, ScaleMode, Double)] = []
        for root in 0..<12 {
            for mode in ScaleMode.allCases {
                let pcs = Set(mode.intervals.map { MusicTheory.positiveMod(root + $0, 12) })
                let inside = (0..<12).reduce(0.0) { $0 + (pcs.contains($1) ? chroma[$1] : 0) }
                let outside = total - inside
                let tonic = chroma[root] / total
                let coverage = inside / total
                let pentatonicPenalty = mode.intervals.count == 5 ? 0.035 : 0
                let score = coverage - 0.55 * (outside / total) + 0.17 * tonic - pentatonicPenalty
                candidates.append((root, mode, score))
            }
        }
        candidates.sort { $0.2 > $1.2 }
        let best = candidates.first ?? (0, ScaleMode.major, 0.5)
        let second = candidates.dropFirst().first?.2 ?? 0
        let confidence = min(0.99, max(0.20, 0.55 + (best.2 - second) * 2.6))
        return KeyEstimate(rootPitchClass: best.0, mode: best.1, confidence: confidence)
    }

    private struct Candidate {
        let root: Int
        let tones: [Int]
        let name: String
        let degree: Int
    }

    private static func inferChords(frames: [PitchFrame], duration: Double, key: KeyEstimate) -> [ChordEstimate] {
        let scale = key.mode.harmonicIntervals
        guard scale.count == 7 else { return [] }
        let candidates = chordCandidates(root: key.rootPitchClass, scale: scale)
        let window = 1.25
        let count = max(1, Int(ceil(duration / window)))
        var result: [ChordEstimate] = []
        var previous: Candidate?

        for segment in 0..<count {
            let start = Double(segment) * window
            let end = min(duration, start + window)
            let local = frames.filter { $0.time >= start && $0.time < end && $0.confidence >= 0.28 }
            var ranked: [(Candidate, Double)] = []

            for candidate in candidates {
                var score = 0.0
                for frame in local {
                    guard let midi = frame.midiNote else { continue }
                    let pc = MusicTheory.positiveMod(midi, 12)
                    let weight = max(0.18, frame.confidence)
                    if candidate.tones.contains(pc) {
                        score += 1.55 * weight
                        if pc == candidate.root { score += 0.18 * weight }
                    } else if scale.contains(where: { MusicTheory.positiveMod(key.rootPitchClass + $0, 12) == pc }) {
                        score += 0.10 * weight
                    } else {
                        score -= 0.32 * weight
                    }
                }

                // Pop/jazz priors: tonic, predominant and dominant functions are preferred.
                if candidate.degree == 0 { score += 0.24 }
                if candidate.degree == 3 || candidate.degree == 4 { score += 0.18 }
                if candidate.degree == 5 { score += 0.12 }

                if let previous {
                    let movement = MusicTheory.positiveMod(candidate.root - previous.root, 12)
                    if candidate.root == previous.root { score += 0.20 }
                    if movement == 5 || movement == 7 { score += 0.40 }
                    if previous.degree == 4 && candidate.degree == 0 { score += 0.50 }
                    if previous.degree == 1 && candidate.degree == 4 { score += 0.42 }
                }
                ranked.append((candidate, score))
            }

            ranked.sort { $0.1 > $1.1 }
            guard let best = ranked.first else { continue }
            let runnerUp = ranked.dropFirst().first?.1 ?? best.1
            let confidence = local.isEmpty ? 0.22 : min(0.96, max(0.30, 0.58 + (best.1 - runnerUp) / max(2.0, Double(local.count))))
            result.append(ChordEstimate(
                startTime: start,
                endTime: max(start + 0.01, end),
                rootPitchClass: best.0.root,
                tones: best.0.tones,
                name: best.0.name,
                confidence: confidence
            ))
            previous = best.0
        }
        return result
    }

    private static func chordCandidates(root: Int, scale: [Int]) -> [Candidate] {
        var result: [Candidate] = []
        for degree in 0..<7 {
            let rootPC = MusicTheory.positiveMod(root + scale[degree], 12)
            let thirdPC = MusicTheory.positiveMod(root + scale[(degree + 2) % 7], 12)
            let fifthPC = MusicTheory.positiveMod(root + scale[(degree + 4) % 7], 12)
            let seventhPC = MusicTheory.positiveMod(root + scale[(degree + 6) % 7], 12)
            let third = MusicTheory.positiveMod(thirdPC - rootPC, 12)
            let fifth = MusicTheory.positiveMod(fifthPC - rootPC, 12)
            let seventh = MusicTheory.positiveMod(seventhPC - rootPC, 12)
            let suffix: String
            if third == 4 && fifth == 7 {
                suffix = seventh == 11 ? "maj7" : (seventh == 10 ? "7" : "")
            } else if third == 3 && fifth == 7 {
                suffix = seventh == 10 ? "m7" : "m"
            } else if third == 3 && fifth == 6 {
                suffix = "m7♭5"
            } else {
                suffix = ""
            }
            result.append(Candidate(
                root: rootPC,
                tones: [rootPC, thirdPC, fifthPC, seventhPC],
                name: "\(MusicTheory.noteName(rootPC))\(suffix)",
                degree: degree
            ))
        }
        return result
    }
}

enum MLPitchAssistantError: LocalizedError {
    case modelMissing
    case audioConversionFailed
    case invalidModelOutput
    case noAudio
    case noStablePitch

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "The Basic Pitch Core ML model is not bundled in this build."
        case .audioConversionFailed:
            return "The vocal could not be converted for AI melody analysis."
        case .invalidModelOutput:
            return "The AI melody model returned an unexpected output."
        case .noAudio:
            return "The selected file does not contain usable audio."
        case .noStablePitch:
            return "The AI model could not find a stable sung melody. Try a cleaner isolated vocal."
        }
    }
}
