import Foundation

/// Modalità di ripetizione. È indipendente dalla riproduzione casuale.
enum RepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one

    /// Ordine del pulsante: disattivata → coda → singolo brano.
    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var systemImage: String {
        self == .one ? "repeat.1" : "repeat"
    }

    var accessibilityLabel: String {
        switch self {
        case .off: return String(localized: "Ripetizione disattivata")
        case .all: return String(localized: "Ripeti la coda")
        case .one: return String(localized: "Ripeti il brano")
        }
    }
}

/// Formato del file e formato con cui l'audio raggiunge davvero l'uscita.
/// Serve a mostrare un'informazione verificabile: l'app non dichiara mai una
/// riproduzione bit-perfect.
struct AudioFormatInfo: Equatable {
    let sourceSampleRate: Int
    let sourceBitDepth: Int
    let outputSampleRate: Double
    let outputName: String

    /// Vero se iOS sta convertendo la frequenza di campionamento.
    var isResampled: Bool {
        abs(Double(sourceSampleRate) - outputSampleRate) > 1
    }

    var sourceDescription: String {
        "FLAC \(sourceBitDepth) bit · \(Self.formatKilohertz(Double(sourceSampleRate))) kHz"
    }

    var outputDescription: String {
        let rate = Self.formatKilohertz(outputSampleRate)
        if isResampled {
            return String(localized: "Uscita \(rate) kHz, ricampionata · \(outputName)")
        }
        return String(localized: "Uscita \(rate) kHz · \(outputName)")
    }

    /// 44100 → "44,1"; 96000 → "96".
    static func formatKilohertz(_ hertz: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: hertz / 1000)) ?? "\(hertz / 1000)"
    }
}

/// Stato salvato per riprendere la sessione alla riapertura dell'app.
struct PlaybackSession: Codable {
    var queue: PlaybackQueueManager
    var position: TimeInterval
}
