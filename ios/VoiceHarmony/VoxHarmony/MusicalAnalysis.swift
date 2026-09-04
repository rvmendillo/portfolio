import Foundation
import AVFoundation

enum ScaleMode: String, CaseIterable {
    case major
    case minor
    case majorPentatonic
    case minorPentatonic

    var displayName: String {
        switch self {
        case .major: return "Major"
        case .minor: return "Minor"
        case .majorPentatonic: return "Major Pentatonic"
        case .minorPentatonic: return "Minor Pentatonic"
        }
    }

    var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        case .majorPentatonic: return [0, 2, 4, 7, 9]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        }
    }

    var harmonicIntervals: [Int] {
        switch self {
        case .major, .majorPentatonic:
            return ScaleMode.major.intervals
        case .minor, .minorPentatonic:
            return ScaleMode.minor.intervals
        }
    }

    var pentatonicIntervals: [Int] {
        switch self {
        case .major, .majorPentatonic:
            return ScaleMode.majorPentatonic.intervals
        case .minor, .minorPentatonic:
            return ScaleMode.minorPentatonic.intervals
        }
    }
}

struct KeyEstimate {
    let rootPitchClass: Int
    let mode: ScaleMode
    let confidence: Double

    var displayName: String {
        "\(MusicTheory.noteName(rootPitchClass)) \(mode.displayName)"
    }
}

struct PitchFrame {
    let time: Double
    let midiNote: Int?
    let confidence: Double
}

struct ChordEstimate {
    let startTime: Double
    let endTime: Double
    let rootPitchClass: Int
    let tones: [Int]
    let name: String
    let confidence: Double
}

struct MusicalAnalysis {
    let key: KeyEstimate
    let frames: [PitchFrame]
    let chords: [ChordEstimate]

    func pitchFrame(at time: Double) -> PitchFrame? {
        guard !frames.isEmpty else { return nil }
        var low = 0
        var high = frames.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if frames[mid].time <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return frames[low]
    }

    func chord(at time: Double) -> ChordEstimate? {
        chords.first(where: { time >= $0.startTime && time < $0.endTime }) ?? chords.last
    }
}

enum MusicTheory {
    static let noteNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    static func noteName(_ pitchClass: Int) -> String {
        noteNames[positiveMod(pitchClass, 12)]
    }

    static func positiveMod(_ value: Int, _ modulus: Int) -> Int {
        let result = value % modulus
        return result >= 0 ? result : result + modulus
    }

    static func contains(_ midiNote: Int, root: Int, intervals: [Int]) -> Bool {
        let pc = positiveMod(midiNote, 12)
        return intervals.contains { positiveMod(root + $0, 12) == pc }
    }

    static func scaleMIDINotes(around midi: Int, root: Int, intervals: [Int], radius: Int = 30) -> [Int] {
        let lower = max(0, midi - radius)
        let upper = min(127, midi + radius)
        return Array(lower...upper).filter { contains($0, root: root, intervals: intervals) }
    }

    static func movedScaleDegree(from midi: Int, by steps: Int, root: Int, intervals: [Int]) -> Int {
        let notes = scaleMIDINotes(around: midi, root: root, intervals: intervals, radius: 36)
        guard !notes.isEmpty else { return midi }
        let nearestIndex = notes.indices.min { lhs, rhs in
            abs(notes[lhs] - midi) < abs(notes[rhs] - midi)
        } ?? 0
        let targetIndex = min(max(0, nearestIndex + steps), notes.count - 1)
        return notes[targetIndex]
    }
}

struct MelodyAnalyzer {
    static func analyze(sourceURL: URL) throws -> MusicalAnalysis {
        let file = try AVAudioFile(forReading: sourceURL)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MelodyAnalysisError.unsupportedFormat
        }

        let chunkFrames: AVAudioFrameCount = 4_096
        var frames: [PitchFrame] = []
        var chroma = Array(repeating: 0.0, count: 12)
        let duration = Double(file.length) / format.sampleRate

        while file.framePosition < file.length {
            let remaining = file.length - file.framePosition
            let capacity = AVAudioFrameCount(min(Int64(chunkFrames), remaining))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw MelodyAnalysisError.bufferCreationFailed
            }
            let startFrame = file.framePosition
            try file.read(into: buffer, frameCount: capacity)
            if buffer.frameLength == 0 { break }

            let time = Double(startFrame) / format.sampleRate
            let result = estimatePitch(buffer: buffer, sampleRate: format.sampleRate)
            let midi = result.frequency.map { frequency in
                Int((69.0 + 12.0 * log2(frequency / 440.0)).rounded())
            }
            let safeMIDI = midi.flatMap { (0...127).contains($0) ? $0 : nil }
            frames.append(PitchFrame(time: time, midiNote: safeMIDI, confidence: result.confidence))

            if let safeMIDI, result.confidence >= 0.50 {
                chroma[MusicTheory.positiveMod(safeMIDI, 12)] += max(0.15, result.confidence)
            }
        }

        guard frames.contains(where: { $0.midiNote != nil }) else {
            throw MelodyAnalysisError.noStablePitch
        }

        let key = estimateKey(chroma: chroma)
        let chords = inferChords(frames: frames, duration: duration, key: key)
        return MusicalAnalysis(key: key, frames: frames, chords: chords)
    }

    private static func estimatePitch(buffer: AVAudioPCMBuffer, sampleRate: Double) -> (frequency: Double?, confidence: Double) {
        guard let channels = buffer.floatChannelData else { return (nil, 0) }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= 512 else { return (nil, 0) }

        let downsample = 4
        var samples: [Float] = []
        samples.reserveCapacity(frameCount / downsample + 1)
        var index = 0
        while index < frameCount {
            var value: Float = 0
            for channel in 0..<channelCount {
                value += channels[channel][index]
            }
            samples.append(value / Float(channelCount))
            index += downsample
        }

        let mean = samples.reduce(0, +) / Float(samples.count)
        var energy: Double = 0
        for i in samples.indices {
            samples[i] -= mean
            let v = Double(samples[i])
            energy += v * v
        }
        let rms = sqrt(energy / Double(samples.count))
        guard rms > 0.006 else { return (nil, 0) }

        let effectiveRate = sampleRate / Double(downsample)
        let minLag = max(2, Int(effectiveRate / 1_000.0))
        let maxLag = min(samples.count / 2, Int(effectiveRate / 70.0))
        guard maxLag > minLag else { return (nil, 0) }

        var bestLag = 0
        var bestScore = 0.0

        for lag in minLag...maxLag {
            var correlation = 0.0
            var leftEnergy = 0.0
            var rightEnergy = 0.0
            let upper = samples.count - lag
            if upper <= 32 { continue }
            for i in 0..<upper {
                let a = Double(samples[i])
                let b = Double(samples[i + lag])
                correlation += a * b
                leftEnergy += a * a
                rightEnergy += b * b
            }
            let denominator = sqrt(leftEnergy * rightEnergy) + 1e-12
            let score = correlation / denominator
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        guard bestLag > 0, bestScore >= 0.52 else { return (nil, max(0, bestScore)) }
        return (effectiveRate / Double(bestLag), min(1, bestScore))
    }

    private static func estimateKey(chroma: [Double]) -> KeyEstimate {
        let total = max(0.0001, chroma.reduce(0, +))
        var candidates: [(root: Int, mode: ScaleMode, score: Double)] = []

        for root in 0..<12 {
            for mode in ScaleMode.allCases {
                let scalePCs = Set(mode.intervals.map { MusicTheory.positiveMod(root + $0, 12) })
                var inside = 0.0
                var outside = 0.0
                for pc in 0..<12 {
                    if scalePCs.contains(pc) {
                        inside += chroma[pc]
                    } else {
                        outside += chroma[pc]
                    }
                }
                let tonic = chroma[root] / total
                let coverage = inside / total
                let penalty = outside / total
                let pentatonicAdjustment = mode.intervals.count == 5 ? -0.035 : 0.0
                let score = coverage - 0.58 * penalty + 0.15 * tonic + pentatonicAdjustment
                candidates.append((root, mode, score))
            }
        }

        candidates.sort { $0.score > $1.score }
        let best = candidates.first ?? (0, .major, 0.5)
        let second = candidates.dropFirst().first?.score ?? 0
        let confidence = min(0.99, max(0.15, 0.48 + (best.score - second) * 2.4))
        return KeyEstimate(rootPitchClass: best.root, mode: best.mode, confidence: confidence)
    }

    private struct ChordCandidate {
        let root: Int
        let tones: [Int]
        let name: String
    }

    private static func inferChords(frames: [PitchFrame], duration: Double, key: KeyEstimate) -> [ChordEstimate] {
        let scale = key.mode.harmonicIntervals
        let candidates = chordCandidates(root: key.rootPitchClass, scale: scale)
        guard !candidates.isEmpty else { return [] }

        let segmentDuration = 1.5
        let segmentCount = max(1, Int(ceil(duration / segmentDuration)))
        var result: [ChordEstimate] = []
        var previousRoot: Int?

        for segment in 0..<segmentCount {
            let start = Double(segment) * segmentDuration
            let end = min(duration, start + segmentDuration)
            let notes = frames.filter { $0.time >= start && $0.time < end }.compactMap { frame -> (Int, Double)? in
                guard let midi = frame.midiNote else { return nil }
                return (MusicTheory.positiveMod(midi, 12), max(0.15, frame.confidence))
            }

            var scored: [(ChordCandidate, Double)] = []
            for candidate in candidates {
                var score = 0.0
                for (pc, weight) in notes {
                    if candidate.tones.contains(pc) {
                        score += 1.4 * weight
                    } else if scale.contains(where: { MusicTheory.positiveMod(key.rootPitchClass + $0, 12) == pc }) {
                        score += 0.14 * weight
                    } else {
                        score -= 0.35 * weight
                    }
                }
                if let previousRoot {
                    let movement = MusicTheory.positiveMod(candidate.root - previousRoot, 12)
                    if movement == 0 { score += 0.30 }
                    if movement == 5 || movement == 7 { score += 0.48 }
                    if movement == 2 || movement == 10 { score += 0.16 }
                }
                scored.append((candidate, score))
            }

            scored.sort { $0.1 > $1.1 }
            let best = scored.first ?? (candidates[0], 0)
            let runnerUp = scored.dropFirst().first?.1 ?? best.1
            let confidence = notes.isEmpty ? 0.20 : min(0.95, max(0.25, 0.55 + (best.1 - runnerUp) / max(2.0, Double(notes.count))))
            result.append(ChordEstimate(
                startTime: start,
                endTime: max(start + 0.01, end),
                rootPitchClass: best.0.root,
                tones: best.0.tones,
                name: best.0.name,
                confidence: confidence
            ))
            previousRoot = best.0.root
        }
        return result
    }

    private static func chordCandidates(root: Int, scale: [Int]) -> [ChordCandidate] {
        guard scale.count == 7 else { return [] }
        var result: [ChordCandidate] = []
        for degree in 0..<7 {
            let rootPC = MusicTheory.positiveMod(root + scale[degree], 12)
            let thirdPC = MusicTheory.positiveMod(root + scale[(degree + 2) % 7], 12)
            let fifthPC = MusicTheory.positiveMod(root + scale[(degree + 4) % 7], 12)
            let seventhPC = MusicTheory.positiveMod(root + scale[(degree + 6) % 7], 12)
            let third = MusicTheory.positiveMod(thirdPC - rootPC, 12)
            let fifth = MusicTheory.positiveMod(fifthPC - rootPC, 12)
            let seventh = MusicTheory.positiveMod(seventhPC - rootPC, 12)

            let quality: String
            if third == 4 && fifth == 7 {
                quality = seventh == 11 ? "maj7" : (seventh == 10 ? "7" : "")
            } else if third == 3 && fifth == 7 {
                quality = seventh == 10 ? "m7" : "m"
            } else if third == 3 && fifth == 6 {
                quality = "m7♭5"
            } else {
                quality = ""
            }
            result.append(ChordCandidate(
                root: rootPC,
                tones: [rootPC, thirdPC, fifthPC, seventhPC],
                name: "\(MusicTheory.noteName(rootPC))\(quality)"
            ))
        }
        return result
    }
}

enum MelodyAnalysisError: LocalizedError {
    case unsupportedFormat
    case bufferCreationFailed
    case noStablePitch

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "The vocal has an audio format VoxHarmony cannot analyze."
        case .bufferCreationFailed:
            return "VoxHarmony could not create a buffer for melody analysis."
        case .noStablePitch:
            return "No stable sung melody was detected. Try a cleaner isolated vocal with less background music."
        }
    }
}
