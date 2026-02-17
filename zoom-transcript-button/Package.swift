// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "zoom-transcript-save",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "zoom-transcript-save", targets: ["zoom-transcript-save"]),
    ],
    targets: [
        .executableTarget(
            name: "zoom-transcript-save",
            path: "Sources/zoom-transcript-save"
        ),
    ]
)
