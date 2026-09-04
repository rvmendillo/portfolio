import Foundation

enum HarmonyVoiceKind: String, Hashable {
    case solfegeUpper
    case solfegeLower
    case pentatonicUpper
    case pentatonicLower
    case jazzUpper
    case jazzLower
    case octaveLower
    case octaveUpper
}

struct HarmonyVoice: Hashable {
    let kind: HarmonyVoiceKind
    let gain: Float
    let pan: Float
}

struct HarmonyPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let voices: [HarmonyVoice]

    static let presets: [HarmonyPreset] = [
        HarmonyPreset(
            id: "pop-pentatonic",
            name: "Pop + Pentatonic",
            subtitle: "Diatonic upper voice + pentatonic lower voice",
            symbol: "wand.and.stars",
            voices: [
                HarmonyVoice(kind: .solfegeUpper, gain: 0.58, pan: 0.42),
                HarmonyVoice(kind: .pentatonicLower, gain: 0.54, pan: -0.42)
            ]
        ),
        HarmonyPreset(
            id: "pop-solfege",
            name: "Pop Solfège",
            subtitle: "Scale-aware upper and lower thirds",
            symbol: "music.note.list",
            voices: [
                HarmonyVoice(kind: .solfegeUpper, gain: 0.58, pan: 0.40),
                HarmonyVoice(kind: .solfegeLower, gain: 0.50, pan: -0.40)
            ]
        ),
        HarmonyPreset(
            id: "pentatonic",
            name: "Pentatonic Stack",
            subtitle: "Open pentatonic upper and lower movement",
            symbol: "circle.grid.cross",
            voices: [
                HarmonyVoice(kind: .pentatonicUpper, gain: 0.50, pan: 0.48),
                HarmonyVoice(kind: .pentatonicLower, gain: 0.56, pan: -0.48)
            ]
        ),
        HarmonyPreset(
            id: "jazz-color",
            name: "Jazz Color",
            subtitle: "Chord-aware guide tones, 7ths and extensions",
            symbol: "sparkles",
            voices: [
                HarmonyVoice(kind: .jazzUpper, gain: 0.52, pan: 0.44),
                HarmonyVoice(kind: .jazzLower, gain: 0.46, pan: -0.44)
            ]
        ),
        HarmonyPreset(
            id: "pop-jazz-stack",
            name: "Pop + Jazz",
            subtitle: "Pop third above with chord-color voice below",
            symbol: "music.quarternote.3",
            voices: [
                HarmonyVoice(kind: .solfegeUpper, gain: 0.52, pan: 0.36),
                HarmonyVoice(kind: .jazzLower, gain: 0.44, pan: -0.46),
                HarmonyVoice(kind: .jazzUpper, gain: 0.28, pan: 0.62)
            ]
        ),
        HarmonyPreset(
            id: "wide-halo",
            name: "Wide Halo",
            subtitle: "Adaptive harmony plus soft octave doubles",
            symbol: "person.3.sequence.fill",
            voices: [
                HarmonyVoice(kind: .pentatonicLower, gain: 0.42, pan: -0.58),
                HarmonyVoice(kind: .solfegeUpper, gain: 0.48, pan: 0.44),
                HarmonyVoice(kind: .octaveLower, gain: 0.18, pan: -0.18),
                HarmonyVoice(kind: .octaveUpper, gain: 0.14, pan: 0.18)
            ]
        )
    ]
}

enum AdaptiveHarmonyPlanner {
    static func semitones(
        for voice: HarmonyVoiceKind,
        melodyMIDI: Int,
        analysis: MusicalAnalysis,
        time: Double
    ) -> Double {
        let key = analysis.key
        switch voice {
        case .solfegeUpper:
            let target = MusicTheory.movedScaleDegree(
                from: melodyMIDI,
                by: 2,
                root: key.rootPitchClass,
                intervals: key.mode.harmonicIntervals
            )
            return Double(target - melodyMIDI)

        case .solfegeLower:
            let target = MusicTheory.movedScaleDegree(
                from: melodyMIDI,
                by: -2,
                root: key.rootPitchClass,
                intervals: key.mode.harmonicIntervals
            )
            return Double(target - melodyMIDI)

        case .pentatonicUpper:
            let target = MusicTheory.movedScaleDegree(
                from: melodyMIDI,
                by: 2,
                root: key.rootPitchClass,
                intervals: key.mode.pentatonicIntervals
            )
            return Double(target - melodyMIDI)

        case .pentatonicLower:
            let target = MusicTheory.movedScaleDegree(
                from: melodyMIDI,
                by: -2,
                root: key.rootPitchClass,
                intervals: key.mode.pentatonicIntervals
            )
            return Double(target - melodyMIDI)

        case .jazzUpper:
            return Double(jazzTarget(
                melodyMIDI: melodyMIDI,
                direction: 1,
                analysis: analysis,
                time: time
            ) - melodyMIDI)

        case .jazzLower:
            return Double(jazzTarget(
                melodyMIDI: melodyMIDI,
                direction: -1,
                analysis: analysis,
                time: time
            ) - melodyMIDI)

        case .octaveLower:
            return -12
        case .octaveUpper:
            return 12
        }
    }

    private static func jazzTarget(
        melodyMIDI: Int,
        direction: Int,
        analysis: MusicalAnalysis,
        time: Double
    ) -> Int {
        let chord = analysis.chord(at: time)
        let key = analysis.key
        var allowedPCs = Set(chord?.tones ?? [])

        let scale = key.mode.harmonicIntervals
        let melodyPC = MusicTheory.positiveMod(melodyMIDI, 12)
        if let melodyDegree = scale.firstIndex(where: {
            MusicTheory.positiveMod(key.rootPitchClass + $0, 12) == melodyPC
        }) {
            let ninthIndex = (melodyDegree + 1) % scale.count
            allowedPCs.insert(MusicTheory.positiveMod(key.rootPitchClass + scale[ninthIndex], 12))
        }

        if allowedPCs.isEmpty {
            return MusicTheory.movedScaleDegree(
                from: melodyMIDI,
                by: direction > 0 ? 2 : -2,
                root: key.rootPitchClass,
                intervals: scale
            )
        }

        if direction > 0 {
            for candidate in (melodyMIDI + 2)...min(127, melodyMIDI + 10) {
                let pc = MusicTheory.positiveMod(candidate, 12)
                if pc != melodyPC && allowedPCs.contains(pc) {
                    return candidate
                }
            }
            return min(127, melodyMIDI + 7)
        } else {
            let lower = max(0, melodyMIDI - 10)
            if melodyMIDI - 2 >= lower {
                for candidate in stride(from: melodyMIDI - 2, through: lower, by: -1) {
                    let pc = MusicTheory.positiveMod(candidate, 12)
                    if pc != melodyPC && allowedPCs.contains(pc) {
                        return candidate
                    }
                }
            }
            return max(0, melodyMIDI - 5)
        }
    }
}
