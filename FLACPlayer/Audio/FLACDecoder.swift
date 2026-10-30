import AVFoundation
import CFLAC

enum FLACError: LocalizedError, Equatable {
    case fileNotReadable
    case notFLAC
    case outOfMemory
    case decodingFailed
    case unsupportedChannels(Int)
    case seekFailed
    case integrityMismatch

    init(status: Int32, channels: Int = 0) {
        switch status {
        case CFLAC_ERR_OPEN: self = .fileNotReadable
        case CFLAC_ERR_NOT_FLAC: self = .notFLAC
        case CFLAC_ERR_MEMORY: self = .outOfMemory
        case CFLAC_ERR_CHANNELS: self = .unsupportedChannels(channels)
        case CFLAC_ERR_SEEK: self = .seekFailed
        case CFLAC_ERR_MD5: self = .integrityMismatch
        default: self = .decodingFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .fileNotReadable:
            return String(localized: "Il file non esiste più o non è leggibile.")
        case .notFLAC:
            return String(localized: "Il file non è un FLAC valido oppure è danneggiato.")
        case .outOfMemory:
            return String(localized: "Memoria insufficiente per leggere il file.")
        case .decodingFailed:
            return String(localized: "Il file è danneggiato e non può essere riprodotto.")
        case .unsupportedChannels(let channels):
            return String(localized: "Audio a \(channels) canali non supportato: sono riproducibili solo brani mono e stereo.")
        case .seekFailed:
            return String(localized: "Impossibile spostarsi in questo punto del brano.")
        case .integrityMismatch:
            return String(localized: "L'audio non corrisponde alla firma MD5 del file.")
        }
    }
}

/// Formato di un file FLAC.
struct FLACStreamInfo: Equatable {
    let sampleRate: Int
    let channels: Int
    let bitDepth: Int
    let totalFrames: Int64

    var duration: TimeInterval {
        sampleRate > 0 ? Double(totalFrames) / Double(sampleRate) : 0
    }
}

/// Decodifica in streaming di un singolo file. Non è thread-safe: ogni istanza
/// va usata da una sola coda, come fa `AudioEngineManager`.
final class FLACDecoder {
    let info: FLACStreamInfo
    private let handle: OpaquePointer

    init(url: URL) throws {
        var rawInfo = cflac_info()
        var status: Int32 = CFLAC_OK
        let opened: OpaquePointer? = url.withUnsafeFileSystemRepresentation { path in
            cflac_stream_open(path, &rawInfo, &status)
        }
        guard let opened else {
            throw FLACError(status: status, channels: Int(rawInfo.channels))
        }
        handle = opened
        info = FLACStreamInfo(rawInfo)
    }

    deinit {
        cflac_stream_close(handle)
    }

    /// Riempie il buffer e restituisce i frame scritti: 0 significa fine del file.
    func read(into buffer: AVAudioPCMBuffer) throws -> Int {
        guard let channelData = buffer.floatChannelData else {
            throw FLACError.decodingFailed
        }
        let pointers: [UnsafeMutablePointer<Float>?] = (0..<info.channels).map { channelData[$0] }
        let count = cflac_stream_read(handle, pointers, buffer.frameCapacity)
        guard count >= 0 else {
            throw FLACError(status: Int32(count))
        }
        buffer.frameLength = AVAudioFrameCount(count)
        return Int(count)
    }

    func seek(toFrame frame: Int64) throws {
        let status = cflac_stream_seek(handle, UInt64(max(0, frame)))
        guard status == CFLAC_OK else {
            throw FLACError(status: status)
        }
    }

    /// Errori di stream incontrati finora: un valore maggiore di zero indica un file danneggiato.
    var errorCount: Int {
        Int(cflac_stream_error_count(handle))
    }

    /// Decodifica tutto il file e lo confronta con la firma MD5 di STREAMINFO.
    static func verify(url: URL) throws -> Int64 {
        var frames: UInt64 = 0
        let status = url.withUnsafeFileSystemRepresentation { path in
            cflac_verify_file(path, &frames)
        }
        guard status == CFLAC_OK else {
            throw FLACError(status: status)
        }
        return Int64(frames)
    }
}

extension FLACStreamInfo {
    init(_ raw: cflac_info) {
        self.init(
            sampleRate: Int(raw.sample_rate),
            channels: Int(raw.channels),
            bitDepth: Int(raw.bits_per_sample),
            totalFrames: Int64(raw.total_frames)
        )
    }
}
