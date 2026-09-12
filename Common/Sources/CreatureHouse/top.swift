import ArgumentParser
import AsyncHTTPClient
import Foundation
import Logging
import Observability
import ServiceLifecycle

@main
struct CreatureHouse: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "creature-house",
        abstract: "The house, for Beaky's Virtual World",
        discussion: """
            Follows Home Assistant and tells Creature World what the house sees — doors,
            motion, people, the temperature, what the cameras noticed — and sets the lights
            when someone asks a bird to. Home Assistant's token comes from HA_TOKEN.

            🦜 Bawk!
            """,
        version: CreatureHouseBuildInfo.version,
        helpNames: .shortAndLong
    )

    @Option(
        name: [.customShort("c"), .long],
        help: "Path to the house JSON configuration (default /etc/creature/house.json)")
    var config: String = "/etc/creature/house.json"

    @Option(name: .long, help: "Log level (trace, debug, info, notice, warning, error, critical)")
    var logLevel: String = "info"

    mutating func run() async throws {
        let observabilityServices = try bootstrapObservability(serviceName: "creature-house")
        var logger = Logger(label: "creature-house")
        logger.logLevel = Logger.Level(rawValue: logLevel) ?? .info

        let configuration = try HouseConfiguration.load(from: URL(fileURLWithPath: config))
        guard let token = ProcessInfo.processInfo.environment["HA_TOKEN"], !token.isEmpty else {
            logger.critical("\(HouseConfigurationError.missingToken.localizedDescription)")
            throw HouseConfigurationError.missingToken
        }
        logger.info(
            "creature-house \(CreatureHouseBuildInfo.version)",
            metadata: [
                "home_assistant.url": "\(configuration.homeAssistantURL)",
                "world.url": "\(configuration.worldURL)",
                "house.id": "\(configuration.houseID.rawValue)",
                "mappings": "\(configuration.mappings.count)",
                "scenes": "\(configuration.offersScenes)",
            ])

        var clientConfiguration = HTTPClient.Configuration()
        clientConfiguration.timeout = .init(connect: .seconds(10), read: .seconds(120))
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton, configuration: clientConfiguration,
            backgroundActivityLogger: logger)
        let house = HouseService(
            configuration: configuration, token: token, client: client, logger: logger)
        let group = ServiceGroup(
            services: observabilityServices + [house],
            gracefulShutdownSignals: [.sigterm],
            cancellationSignals: [.sigint],
            logger: logger)
        try await group.run()
    }
}

enum CreatureHouseBuildInfo {
    static let version = "0.1.2"
}
