// swift-tools-version:5.9

import PackageDescription


let package = Package(
    name: "creature-console",
    platforms: [
        .macOS(.v14),
      ],
    products: [

        .library(
            name: "Common",
            targets: ["Common"]),

    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [

        .target(name: "Common",
                dependencies: [],
                exclude: ["README.md", "Controller/Server/GRPC/"]),

        .executableTarget(
            name: "creature-cli",
            dependencies: ["Common",
                           .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CreatureCLI/",
            exclude: ["README.md"]),

            .target(
                name: "Creature Console",
                dependencies: ["Common"],
                path: "Sources/Creature Console/",
                exclude: ["README.md"]),
    ]
)
