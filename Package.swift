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
        .package(url: "https://github.com/auth0/SimpleKeychain", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "CreatureConsole",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "PlaylistRuntime", package: "Common"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "LoggingOSLog", package: "swift-log-oslog"),
                .product(name: "SimpleKeychain", package: "SimpleKeychain"),
            ],
            path: "Sources/Creature Console",
            // Test files are colocated with the app sources but belong to the Xcode test
            // target, not this SPM executable. They `@testable import Creature_Console`, which
            // doesn't exist as an SPM module, so every *Tests.swift here must be excluded from
            // `swift build`. IMPORTANT: add new colocated test files to this list or the `Swift`
            // CI workflow breaks.
            exclude: [
                "README.md",
                "Assets.xcassets",
                "Credits.rtfd",
                // Colocated test files (Xcode test-target only)
                "Controller/AppStateTests.swift",
                "Model/Animation/AnimationMetadataImporterTests.swift",
                "Model/Animation/AnimationMetadataModelTests.swift",
                "Model/Creature/CreatureHealthTests.swift",
                "Model/Creature/CreatureImporterTests.swift",
                "Model/Creature/CreatureModelTests.swift",
                "Model/Playlist/PlaylistImporterTests.swift",
                "Model/Playlist/PlaylistModelTests.swift",
                "Model/Server/LogItemTests.swift",
                "Model/Server/ServerLogImporterTests.swift",
                "Model/Server/ServerLogModelTests.swift",
                "Model/Server/SystemCountersStoreTests.swift",
                "Model/Sounds/SoundImporterTests.swift",
                "Model/Sounds/SoundModelTests.swift",
                "Model/SwiftDataStoreTests.swift",
                "View/ActivityTintTests.swift",
                "View/Animation/TrackViewerTests.swift",
                "View/Creatures/SensorDataTests.swift",
                // Source files that don't build outside the Xcode app target
                "View/Animation/RecordTrackForSession.swift",
                "View/Animation/AnimationRecordingCoordinator.swift",
            ]
        )
    ]
)
