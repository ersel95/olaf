// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Olaf",
    platforms: [
        .iOS(.v17),
        .macOS(.v14) // The engine is UIKit-free, so it also compiles/tests on macOS
    ],
    products: [
        // Single product: engine (ring buffer, NDJSON persistence, OSLog bridge) + network
        // capture (URLProtocol) + in-app viewer (shake → list/detail). Viewer content is
        // gated behind `#if canImport(UIKit)`, so it compiles on every platform.
        .library(name: "Olaf", targets: ["Olaf"])
    ],
    targets: [
        .target(
            name: "Olaf",
            resources: [
                .process("UI/Resources"),
                // SDK privacy manifest for App Store submissions (no data collected; only a
                // file-timestamp read declaration for rotation).
                .copy("PrivacyInfo.xcprivacy")
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
