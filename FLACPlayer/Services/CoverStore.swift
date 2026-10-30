import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Copertine estratte dai FLAC. Il nome del file è l'hash dell'immagine: tutti i
/// brani di un album condividono un'unica copia su disco.
struct CoverStore {
    let paths: AppPaths

    static func url(for coverID: String, in paths: AppPaths) -> URL {
        paths.covers.appendingPathComponent(coverID)
    }

    /// Salva l'immagine se è decodificabile e restituisce il suo identificativo.
    /// Una copertina corrotta non impedisce l'importazione del brano.
    func save(_ data: Data) -> String? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else {
            return nil
        }
        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = Self.url(for: id, in: paths)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                return nil
            }
        }
        return id
    }
}

/// Carica le copertine ridimensionate in background e le tiene in una cache.
final class CoverImageLoader: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()
    private let paths: AppPaths

    init(paths: AppPaths) {
        self.paths = paths
        cache.countLimit = 400
    }

    func cached(coverID: String, pixelSize: Int) -> UIImage? {
        cache.object(forKey: Self.key(coverID, pixelSize))
    }

    func load(coverID: String, pixelSize: Int) async -> UIImage? {
        if let image = cached(coverID: coverID, pixelSize: pixelSize) {
            return image
        }
        let url = CoverStore.url(for: coverID, in: paths)
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsample(url: url, pixelSize: pixelSize)
        }.value
        if let image {
            cache.setObject(image, forKey: Self.key(coverID, pixelSize))
        }
        return image
    }

    private static func key(_ coverID: String, _ pixelSize: Int) -> NSString {
        "\(coverID)-\(pixelSize)" as NSString
    }

    /// Decodifica direttamente alla dimensione richiesta: una copertina da 3000 px
    /// non occupa memoria inutile in una riga da 44 punti.
    private static func downsample(url: URL, pixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ] as [CFString: Any] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }
}
