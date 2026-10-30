import CryptoKit
import Foundation

enum FileHasher {
    private static let chunkSize = 1 << 20

    /// SHA-256 del file, letto a blocchi per non caricarlo in memoria.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let finished: Bool = try autoreleasepool {
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    return true
                }
                hasher.update(data: chunk)
                return false
            }
            if finished { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
