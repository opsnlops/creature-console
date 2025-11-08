// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CreatureConsole",
    platforms: [
        .macOS(.v26), .iOS(.v26), .tvOS(.v26)
    ],
    products: [
        .executable(
            name: "creature-console",
            targets: ["CreatureConsole"]
        )
    ],
    dependencies: [
        .package(path: "./Common"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/chrisaljoudi/swift-log-oslog.git", from: "0.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "CreatureConsole",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "PlaylistRuntime", package: "Common"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "LoggingOSLog", package: "swift-log-oslog"),
            ],
            path: "Sources/Creature Console",
            exclude: [
                "README.md",
                "Assets.xcassets",
                "Credits.rtfd",
                "Model/Server/SystemCountersStoreTests.swift",
                "Model/Server/LogItemTests.swift",
                "Model/Creature/CreatureHealthTests.swift",
                "View/Animation/TrackViewerTests.swift",
                "View/Creatures/SensorDataTests.swift",
                "View/Animation/RecordTrackForSession.swift",
                "View/Animation/AnimationRecordingCoordinator.swift"
            ]
        )
    ]
)
