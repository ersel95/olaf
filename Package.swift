// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Olaf",
    platforms: [
        .iOS(.v17),
        .macOS(.v14) // Core, UIKit'siz olduğu için macOS'ta da test edilebilir
    ],
    products: [
        // Çekirdek motor (UIKit/SwiftUI'sız, her platformda).
        .library(name: "OlafCore", targets: ["OlafCore"]),
        // In-app viewer (shake → liste/detay, filtre, paylaşım). iOS hedefli; içerik `#if canImport(UIKit)` gate'li.
        .library(name: "OlafUI", targets: ["OlafUI"]),
        // Opsiyonel network capture (URLProtocol). İstek/yanıtları .network kategorisinde,
        // BankingRedactor'dan geçerek Olaf'a loglar. UIKit'siz, her platformda.
        .library(name: "OlafNetwork", targets: ["OlafNetwork"]),
        // Opsiyonel bug-reporter upload katmanı (screenshot → banner → multipart upload).
        // OPT-IN, varsayılan KAPALI. OlafCore'a bağımlı; recursion önleme için OlafNetwork'e zayıf bağlı.
        .library(name: "OlafUpload", targets: ["OlafUpload"])
    ],
    targets: [
        .target(
            name: "OlafCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "OlafUI",
            dependencies: ["OlafCore", "OlafUpload"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "OlafNetwork",
            dependencies: ["OlafCore"]
        ),
        .target(
            name: "OlafUpload",
            dependencies: ["OlafCore", "OlafNetwork"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "OlafCoreTests",
            dependencies: ["OlafCore"]
        ),
        .testTarget(
            name: "OlafUITests",
            dependencies: ["OlafUI"]
        ),
        .testTarget(
            name: "OlafNetworkTests",
            dependencies: ["OlafNetwork"]
        ),
        .testTarget(
            name: "OlafUploadTests",
            dependencies: ["OlafUpload"]
        )
    ]
)
