// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LogFox",
    platforms: [
        .iOS(.v17),
        .macOS(.v14) // Core, UIKit'siz olduğu için macOS'ta da test edilebilir
    ],
    products: [
        // Çekirdek motor (UIKit/SwiftUI'sız, her platformda).
        .library(name: "LogFoxCore", targets: ["LogFoxCore"]),
        // In-app viewer (shake → liste/detay, filtre, paylaşım). iOS hedefli; içerik `#if canImport(UIKit)` gate'li.
        .library(name: "LogFoxUI", targets: ["LogFoxUI"]),
        // Opsiyonel network capture (URLProtocol). İstek/yanıtları .network kategorisinde,
        // BankingRedactor'dan geçerek LogFox'a loglar. UIKit'siz, her platformda.
        .library(name: "LogFoxNetwork", targets: ["LogFoxNetwork"])
    ],
    targets: [
        .target(
            name: "LogFoxCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "LogFoxUI",
            dependencies: ["LogFoxCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "LogFoxNetwork",
            dependencies: ["LogFoxCore"]
        ),
        .testTarget(
            name: "LogFoxCoreTests",
            dependencies: ["LogFoxCore"]
        ),
        .testTarget(
            name: "LogFoxUITests",
            dependencies: ["LogFoxUI"]
        ),
        .testTarget(
            name: "LogFoxNetworkTests",
            dependencies: ["LogFoxNetwork"]
        )
    ]
)
