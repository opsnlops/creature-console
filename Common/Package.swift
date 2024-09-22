// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Common",
    platforms: [
        .macOS(.v14), .iOS(.v17),
    ],
    products: [
        .library(
            name: "Common",
            targets: ["Common"])

    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.8"),
    ],

    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Starscream", package: "Starscream"),
            ],
            exclude: ["README.md"]),

        .executableTarget(
            name: "creature-cli",
            dependencies: [
                "Common",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CreatureCLI/",
            exclude: ["README.md"]),

    ]
)
