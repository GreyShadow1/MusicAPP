import SwiftUI

private struct CoverLoaderKey: EnvironmentKey {
    static let defaultValue: CoverImageLoader? = nil
}

extension EnvironmentValues {
    var coverLoader: CoverImageLoader? {
        get { self[CoverLoaderKey.self] }
        set { self[CoverLoaderKey.self] = newValue }
    }
}

/// Copertina quadrata, con un segnaposto quando manca.
struct CoverArtView: View {
    let coverID: String?
    let side: CGFloat
    var cornerRadius: CGFloat = 6

    @Environment(\.coverLoader) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage? = nil

    private var pixelSize: Int {
        Int(side * displayScale)
    }

    var body: some View {
        ZStack {
            Theme.surface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.4, weight: .light))
                    .foregroundColor(Theme.secondaryText)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: "\(coverID ?? "")-\(pixelSize)") {
            guard let coverID, let loader else {
                image = nil
                return
            }
            image = await loader.load(coverID: coverID, pixelSize: pixelSize)
        }
    }
}
