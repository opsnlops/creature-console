import ArgumentParser
import BeakyCommunicatorCore
import CreatureCommunicatorGateway
import Foundation
import Hummingbird
import Logging
import Observability

@main
struct CreatureCommunicatorGatewayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "creature-communicator-gateway",
        abstract: "Beaky Communicator Gateway for April's Creature Workshop",
        discussion: """
            Runs the narrow synchronization and delivery gateway for Beaky Communicator.

            Configuration precedence is command options, SERVER_HOSTNAME and SERVER_PORT,
            the JSON configuration file, then built-in defaults.

            🦜 Bawk!
            """,
        version: CommunicatorGatewayBuildInfo.current.version,
        helpNames: .shortAndLong
    )

    @Option(
        name: [.customShort("c"), .long],
        help:
            "Path to a Communicator Gateway JSON configuration file (or CREATURE_COMMUNICATOR_GATEWAY_CONFIG)"
    )
    var config: String?

    @Option(name: [.customShort("H"), .long], help: "HTTP bind host (or SERVER_HOSTNAME)")
    var host: String?

    @Option(name: [.customShort("p"), .long], help: "HTTP port (or SERVER_PORT)")
    var port: Int?

    @Option(
        name: .long,
        help: "Log level (trace, debug, info, notice, warning, error, critical)"
    )
    var logLevel: GatewayLogLevel = .debug

    mutating func run() async throws {
        let observabilityServices = try bootstrapObservability(
            serviceName: "creature-communicator-gateway"
        )
        var logger = Logger(label: "creature-communicator-gateway")
        logger.logLevel = logLevel.loggerLevel
        logger.debug("Parsing the command line options")

        let environment = ProcessInfo.processInfo.environment
        let configPath =
            config ?? environment[CommunicatorGatewayConfiguration.configPathEnvironmentKey]
        let configURL = configPath.map { URL(fileURLWithPath: $0) }
        if let configPath {
            logger.debug(
                "Reading Creature Communicator Gateway configuration file",
                metadata: ["config.path": "\(configPath)"]
            )
        } else {
            logger.debug("No configuration file selected; using environment and built-in defaults")
        }

        let resolved = try CommunicatorGatewayConfiguration.load(from: configURL)
            .overriding(host: host, port: port)
        logger.info(
            "Creature Communicator Gateway version \(CommunicatorGatewayBuildInfo.current.version)",
            metadata: ["build.version": "\(CommunicatorGatewayBuildInfo.current.version)"]
        )
        logger.debug(
            "Creature Communicator Gateway configuration resolved",
            metadata: [
                "http.host": "\(resolved.host)",
                "http.port": "\(resolved.port)",
            ]
        )

        let application = makeCommunicatorGatewayApplication(
            registry: ForegroundLeaseRegistry(),
            configuration: resolved,
            services: observabilityServices,
            logger: logger
        )
        try await application.runService()
    }
}

enum GatewayLogLevel: String, ExpressibleByArgument {
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
