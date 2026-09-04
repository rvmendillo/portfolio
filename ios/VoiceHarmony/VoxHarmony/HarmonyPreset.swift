import Foundation

struct HarmonyLayer: Hashable {
    let semitones: Double
    let gain: Float
    let pan: Float
}

struct HarmonyPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let layers: [HarmonyLayer]

    static let presets: [HarmonyPreset] = [
        HarmonyPreset(
            id: "studio",
            name: "Studio Trio",
            subtitle: "Lower 3rd + upper 3rd + soft 5th",
            symbol: "music.mic",
            layers: [
                HarmonyLayer(semitones: -3, gain: 0.50, pan: -0.48),
                HarmonyLayer(semitones: 4, gain: 0.50, pan: 0.48),
                HarmonyLayer(semitones: 7, gain: 0.26, pan: 0.18)
            ]
        ),
        HarmonyPreset(
            id: "warm-duet",
            name: "Warm Duet",
            subtitle: "A close lower harmony",
            symbol: "person.2.wave.2",
            layers: [
                HarmonyLayer(semitones: -3, gain: 0.66, pan: -0.28)
            ]
        ),
        HarmonyPreset(
            id: "bright-duet",
            name: "Bright Duet",
            subtitle: "An upper major-third harmony",
            symbol: "sparkles",
            layers: [
                HarmonyLayer(semitones: 4, gain: 0.64, pan: 0.30)
            ]
        ),
        HarmonyPreset(
            id: "fifths",
            name: "Open Fifths",
            subtitle: "Wide lower and upper fifths",
            symbol: "arrow.up.and.down.and.arrow.left.and.right",
            layers: [
                HarmonyLayer(semitones: -5, gain: 0.42, pan: -0.58),
                HarmonyLayer(semitones: 7, gain: 0.42, pan: 0.58)
            ]
        ),
        HarmonyPreset(
            id: "choir",
            name: "Choir Stack",
            subtitle: "Five layers for a fuller vocal wall",
            symbol: "person.3.sequence.fill",
            layers: [
                HarmonyLayer(semitones: -12, gain: 0.20, pan: -0.10),
                HarmonyLayer(semitones: -5, gain: 0.30, pan: -0.66),
                HarmonyLayer(semitones: -3, gain: 0.42, pan: -0.32),
                HarmonyLayer(semitones: 4, gain: 0.42, pan: 0.32),
                HarmonyLayer(semitones: 7, gain: 0.30, pan: 0.66)
            ]
        ),
        HarmonyPreset(
            id: "octaves",
            name: "Octave Halo",
            subtitle: "Low octave + airy high octave",
            symbol: "circle.hexagongrid.fill",
            layers: [
                HarmonyLayer(semitones: -12, gain: 0.33, pan: -0.34),
                HarmonyLayer(semitones: 12, gain: 0.25, pan: 0.34)
            ]
        )
    ]
}
