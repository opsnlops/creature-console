import ArgumentParser
import Foundation
import Logging
import Observability

@main
struct CreatureWorld: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "creature-world",
        abstract: "Creature World for April's Creature Workshop",
        discussion: """
            Runs the authoritative shared-world simulator for Creature clients.

            Configuration precedence is command options, SERVER_HOSTNAME, SERVER_PORT, and
            MONGODB_URI, the JSON configuration file, then built-in defaults.

            🦜 Bawk!
            """,
        version: CreatureWorldBuildInfo.current.version,
        helpNames: .shortAndLong
    )

    @Option(
        name: [.customShort("c"), .long],
        help: "Path to a Creature World JSON configuration file (or CREATURE_WORLD_CONFIG)"
    )
    var config: String?

    @Option(name: [.customShort("H"), .long], help: "HTTP bind host (or SERVER_HOSTNAME)")
    var host: String?

    @Option(name: [.customShort("p"), .long], help: "HTTP port (or SERVER_PORT)")
    var port: Int?

    @Option(name: .long, help: "MongoDB URI selecting creature_world (or MONGODB_URI)")
    var mongodbURI: String?

    @Option(
        name: .long,
        help: "Log level (trace, debug, info, notice, warning, error, critical)"
    )
    var logLevel: WorldLogLevel = .info

    mutating func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let configPath = config ?? environment[CreatureWorldConfiguration.configPathEnvironmentKey]
        let configURL = configPath.map { URL(fileURLWithPath: $0) }
        let configuration = try CreatureWorldConfiguration.load(from: configURL)
            .overriding(host: host, port: port, mongoURI: mongodbURI)
        let observabilityServices = try bootstrapObservability(serviceName: "creature-world")
        var logger = Logger(label: "creature-world")
        logger.logLevel = logLevel.loggerLevel
        let dependencies = try await CreatureWorldDependencies.live(
            configuration: configuration,
            logger: logger
        )
        let application = makeCreatureWorldApplication(
            dependencies: dependencies,
            services: observabilityServices
        )
        try await application.runService()
    }
}

enum WorldLogLevel: String, ExpressibleByArgument {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    var loggerLevel: Logger.Level {
        switch self {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        case .critical: .critical
        }
    }
}
