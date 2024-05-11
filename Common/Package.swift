// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Common",
    platforms: [
        .macOS(.v14), .iOS(.v17)
    ],
    products: [
        .library(
            name: "Common",
            targets: ["Common"]),

    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    
    targets: [
        .target(
            name: "Common", dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]),

    .executableTarget(
        name: "creature-cli",
        dependencies: ["Common",
                       .product(name: "ArgumentParser", package: "swift-argument-parser"),
                       .product(name: "Logging", package: "swift-log")
        ],
        path: "Sources/CreatureCLI/",
        exclude: ["README.md"]),

    ]
)
