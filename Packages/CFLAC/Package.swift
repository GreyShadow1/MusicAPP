// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CFLAC",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "CFLAC", targets: ["CFLAC"])
    ],
    targets: [
        .target(
            name: "CFLAC",
            path: "Sources/CFLAC",
            // Frammenti inclusi da bitreader.c e lpc.c: non si compilano da soli.
            exclude: ["libFLAC/deduplication"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("flac_headers"),
                .headerSearchPath("libFLAC/include"),
                .define("HAVE_CONFIG_H"),
                .define("FLAC__NO_DLL"),
                .define("NDEBUG")
            ]
        )
    ]
)
