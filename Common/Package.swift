// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Common",
    platforms: [
        .macOS(.v15), .iOS(.v26),
    ],
    products: [
        .library(
            name: "Common",
            targets: ["Common"]),
        .library(
            name: "PlaylistRuntime",
            targets: ["PlaylistRuntime"])

    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
    ],

    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            exclude: ["README.md"]),

        .target(
            name: "PlaylistRuntime",
            dependencies: [
                "Common",
                .product(name: "Logging", package: "swift-log")
            ]),

        .executableTarget(
            name: "creature-cli",
            dependencies: [
                "Common",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CreatureCLI/",
            exclude: ["README.md"]),

        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common",
                "creature-cli",
            ]
        ),
    ]
)
