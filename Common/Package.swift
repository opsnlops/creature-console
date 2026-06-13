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
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.6"),
        .package(
            url: "https://github.com/swift-otel/swift-otel.git",
            from: "1.0.0",
            traits: ["OTLPHTTP"]),
        .package(
            url: "https://github.com/swift-server/swift-service-lifecycle.git",
            from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.4.0"),
        .package(url: "https://github.com/orlandos-nl/MongoKitten.git", from: "7.16.0"),
    ],

    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
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
            name: "MQTTSupport",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MQTTNIO", package: "mqtt-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]),

        .target(
            name: "PlaylistRuntime",
            dependencies: [
                "Common",
                .product(name: "Logging", package: "swift-log"),
            ]),

        .target(
            name: "Observability",
            dependencies: [
                .product(name: "OTel", package: "swift-otel"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ]),

        // MongoDB migration/back-fill building blocks (server-address parsing, connection
        // helper, content-reference extraction). Kept out of Common so MongoKitten doesn't
        // leak into the GUI app; the CLI commands depend on this.
        .target(
            name: "CreatureMigration",
            dependencies: [
                .product(name: "MongoKitten", package: "MongoKitten")
            ],
            path: "Sources/CreatureMigration/"),

        .executableTarget(
            name: "creature-cli",
            dependencies: [
                "Common",
                "CreatureMigration",
                "Observability",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MongoKitten", package: "MongoKitten"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
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
                "MQTTSupport",
                "Observability",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            path: "Sources/CreatureMQTT/",
            exclude: ["README.md", "CHANGELOG.md"]),

        .executableTarget(
            name: "creature-agent",
            dependencies: [
                "Common",
                "MQTTSupport",
                "Observability",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            path: "Sources/CreatureAgent/"),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common",
                "creature-cli",
                "CreatureMigration",
                .product(name: "MongoKitten", package: "MongoKitten"),
            ]
        ),
        .testTarget(
            name: "CreatureAgentTests",
            dependencies: [
                "creature-agent",
                "creature-mqtt",
                .product(name: "MetricsTestKit", package: "swift-metrics"),
            ]
        ),
    ]
)
