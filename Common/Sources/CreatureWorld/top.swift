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
    var logLevel: WorldLogLevel = .debug

    mutating func run() async throws {
        let observabilityServices = try bootstrapObservability(serviceName: "creature-world")
        var logger = Logger(label: "creature-world")
        logger.logLevel = logLevel.loggerLevel
        logger.debug("Parsing the command line options")

        let environment = ProcessInfo.processInfo.environment
        let configPath = config ?? environment[CreatureWorldConfiguration.configPathEnvironmentKey]
        let configURL = configPath.map { URL(fileURLWithPath: $0) }
        if let configPath {
            logger.debug(
                "Reading Creature World configuration file",
                metadata: [
                    "config.path": "\(configPath)",
                    "config.source": config == nil ? "environment" : "command-line",
                ]
            )
        } else {
            logger.debug("No configuration file selected; using environment and built-in defaults")
        }

        let configuration: CreatureWorldConfiguration
        do {
            configuration = try CreatureWorldConfiguration.load(from: configURL)
                .overriding(host: host, port: port, mongoURI: mongodbURI)
        } catch {
            logger.critical(
                "Failed to load Creature World configuration",
                metadata: ["error": "\(error.localizedDescription)"]
            )
            throw error
        }

        logger.info(
            "Creature World version \(CreatureWorldBuildInfo.current.version)",
            metadata: [
                "build.version": "\(CreatureWorldBuildInfo.current.version)",
                "world.schema_version": "\(CreatureWorldBuildInfo.current.schemaVersion)",
            ]
        )
        logger.debug(
            "Creature World configuration resolved",
            metadata: [
                "http.host": "\(configuration.host)",
                "http.host.source":
                    "\(configurationSource(commandLine: host, environment: environment[CreatureWorldConfiguration.hostEnvironmentKey], hasFile: configURL != nil))",
                "http.port": "\(configuration.port)",
                "http.port.source":
                    "\(configurationSource(commandLine: port, environment: environment[CreatureWorldConfiguration.portEnvironmentKey], hasFile: configURL != nil))",
                "mongodb.database": "\(CreatureWorldConfiguration.databaseName)",
                "mongodb.uri.source":
                    "\(configurationSource(commandLine: mongodbURI, environment: environment[CreatureWorldConfiguration.mongoURIEnvironmentKey], hasFile: configURL != nil))",
            ]
        )
        let dependencies: CreatureWorldDependencies
        do {
            logger.debug("Initializing Creature World dependencies")
            dependencies = try await CreatureWorldDependencies.live(
                configuration: configuration,
                logger: logger
            )
            logger.debug("Creature World dependencies initialized")
        } catch {
            logger.critical(
                "Creature World startup failed",
                metadata: ["error": "\(error.localizedDescription)"]
            )
            throw error
        }
        let application = makeCreatureWorldApplication(
            dependencies: dependencies,
            services: observabilityServices
        )
        try await application.runService()
    }

    private func configurationSource<T>(
        commandLine: T?,
        environment: String?,
        hasFile: Bool
    ) -> String {
        if commandLine != nil {
            return "command-line"
        }
        if environment != nil {
            return "environment"
        }
        return hasFile ? "configuration-file-or-default" : "built-in-default"
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
