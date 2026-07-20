// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Olaf",
    platforms: [
        .iOS(.v17),
        .macOS(.v14) // Motor UIKit'siz olduğu için macOS'ta da derlenir/test edilir
    ],
    products: [
        // Tek ürün: motor (ring buffer, NDJSON persistans, OSLog köprüsü) + network capture
        // (URLProtocol) + in-app viewer (shake → liste/detay). Viewer içeriği
        // `#if canImport(UIKit)` gate'li olduğundan her platformda derlenir.
        .library(name: "Olaf", targets: ["Olaf"])
    ],
    targets: [
        .target(
            name: "Olaf",
            resources: [
                .process("UI/Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "OlafTests",
            dependencies: ["Olaf"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
