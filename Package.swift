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
        .library(name: "LogFoxNetwork", targets: ["LogFoxNetwork"]),
        // Opsiyonel Netfox köprüsü — "Choose Package Products"ta ayrı ürün olarak görünür.
        // Tüketici bu ürünü target'a eklerse netfox linklenir ve köprü kullanılabilir olur;
        // init'te tek satır `LogFoxNetfox.install()` ile viewer'a kaydedilir.
        .library(name: "LogFoxNetfox", targets: ["LogFoxNetfox"])
    ],
    dependencies: [
        // Yalnız LogFoxNetfox ürünü seçilince LİNKLENİR; ama resolution sırasında (her tüketicide) checkout edilir.
        // netfox UIKit-only → target bağımlılığı iOS ile koşullanır (macOS'ta derlenmez).
        .package(url: "https://github.com/kasketis/netfox.git", from: "1.21.0")
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
        // Netfox köprüsü — netfox iOS-only olduğu için bağımlılık platformla koşullu; macOS'ta köprü
        // gövdesi `#if canImport(UIKit)` ile boşalır, target yine derlenir.
        .target(
            name: "LogFoxNetfox",
            dependencies: [
                "LogFoxUI",
                .product(name: "netfox", package: "netfox", condition: .when(platforms: [.iOS]))
            ]
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
