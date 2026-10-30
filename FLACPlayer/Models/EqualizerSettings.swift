import Foundation

struct EqualizerPreset: Identifiable, Equatable {
    let name: String
    let gains: [Float]

    var id: String { name }
}

/// Equalizzatore a 10 bande. Spento non altera l'audio.
struct EqualizerSettings: Codable, Equatable {
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let maxGain: Float = 12

    /// Gli stessi valori sono usati dall'app Android.
    static let presets = [
        EqualizerPreset(name: "Piatto", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqualizerPreset(name: "Bassi", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        EqualizerPreset(name: "Rock", gains: [4, 3, 2, 0, -1, -1, 1, 2, 3, 4]),
        EqualizerPreset(name: "Pop", gains: [-1, 0, 1, 3, 4, 3, 1, 0, -1, -1]),
        EqualizerPreset(name: "Jazz", gains: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
        EqualizerPreset(name: "Classica", gains: [3, 2, 1, 0, 0, 0, 0, 1, 2, 3]),
        EqualizerPreset(name: "Elettronica", gains: [5, 4, 1, 0, -2, 1, 0, 1, 4, 5]),
        EqualizerPreset(name: "Voce", gains: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1])
    ]

    var isEnabled = false
    /// `nil` quando i cursori sono stati modificati a mano.
    var presetName: String? = "Piatto"
    var gains: [Float] = Array(repeating: 0, count: 10)

    mutating func apply(_ preset: EqualizerPreset) {
        presetName = preset.name
        gains = preset.gains
    }

    mutating func setGain(_ gain: Float, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = min(max(gain, -Self.maxGain), Self.maxGain)
        presetName = nil
    }

    /// Attenuazione che compensa l'aumento maggiore ed evita la distorsione.
    var headroom: Float {
        isEnabled ? -max(gains.max() ?? 0, 0) : 0
    }
}
