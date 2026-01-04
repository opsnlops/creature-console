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
            targets: ["PlaylistRuntime"]),

    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
        .package(url: "https://github.com/swift-server-community/mqtt-nio", from: "2.12.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.74.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
    ],

    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(
                    name: "NIOCore",
                    package: "swift-nio",
                    condition: .when(platforms: [.linux])),
                .product(
                    name: "NIOPosix",
                    package: "swift-nio",
                    condition: .when(platforms: [.linux])),
                .product(
                    name: "NIOHTTP1",
                    package: "swift-nio",
                    condition: .when(platforms: [.linux])),
                .product(
                    name: "NIOWebSocket",
                    package: "swift-nio",
                    condition: .when(platforms: [.linux])),
                .product(
                    name: "NIOSSL",
                    package: "swift-nio-ssl",
                    condition: .when(platforms: [.linux])),
            ],
            exclude: ["README.md"]),

        .target(
            name: "PlaylistRuntime",
            dependencies: [
                "Common",
                .product(name: "Logging", package: "swift-log"),
            ]),

        .executableTarget(
            name: "creature-cli",
            dependencies: [
                "Common",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(
                    name: "NIOCore",
                    package: "swift-nio",
                    condition: .when(platforms: [.linux])),
                .product(
                    name: "NIOPosix",
                    package: "swift-nio",
                    condition: .when(platforms: [.linux])),
            ],
            path: "Sources/CreatureCLI/",
            exclude: ["README.md"]),

        .executableTarget(
            name: "creature-mqtt",
            dependencies: [
                "Common",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MQTTNIO", package: "mqtt-nio"),
            ],
            path: "Sources/CreatureMQTT/",
            exclude: ["README.md", "CHANGELOG.md"]),

        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common",
                "creature-cli",
            ]
        ),
    ]
)
