import ArgumentParser
import AsyncHTTPClient
import Common
import Foundation
import Logging
import Observability
import ServiceLifecycle

@main
struct CreatureBody: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "creature-body",
        abstract: "The birds' bodies, for Beaky's Virtual World",
        discussion: """
            Follows Creature Server's sensor reports and tells Creature World what each bird's
            body says - its board temperature, its power rails, its motors - as facts on the
            bird, said when they change and forgotten when the bird goes quiet. The birds are
            curious what their sensors read.

            Configuration precedence is command options, then CREATURE_SERVER_HOST,
            CREATURE_SERVER_PORT, CREATURE_SERVER_TLS, CREATURE_PROXY_HOST,
            CREATURE_PROXY_API_KEY, and CREATURE_WORLD_URL, then the JSON configuration
            file, then built-in defaults.

            🦜 Bawk!
            """,
        version: CreatureBodyBuildInfo.version,
        helpNames: .shortAndLong
    )

    @Option(
        name: [.customShort("c"), .long],
        help: "Path to the creature-body JSON configuration (or CREATURE_BODY_CONFIG)")
    var config: String?

    @Option(name: .long, help: "Creature Server host (or CREATURE_SERVER_HOST)")
    var serverHost: String?

    @Option(name: .long, help: "Creature Server port (or CREATURE_SERVER_PORT)")
    var serverPort: Int?

    @Option(name: .long, help: "Creature World API root (or CREATURE_WORLD_URL)")
    var worldURL: String?

    @Option(name: .long, help: "Log level (trace, debug, info, notice, warning, error, critical)")
    var logLevel: String = "info"

    mutating func run() async throws {
        let observabilityServices = try bootstrapObservability(serviceName: "creature-body")
        var logger = Logger(label: "creature-body")
        logger.logLevel = Logger.Level(rawValue: logLevel) ?? .info

        let environment = ProcessInfo.processInfo.environment
        let path = config ?? environment[BodyConfiguration.configPathEnvironmentKey]
        var configuration = try BodyConfiguration.load(from: path.map { URL(fileURLWithPath: $0) })
        if let serverHost { configuration.serverHost = serverHost }
        if let serverPort { configuration.serverPort = serverPort }
        if let worldURL {
            guard let url = URL(string: worldURL) else {
                throw BodyConfigurationError.invalidValue(name: "--world-url", value: worldURL)
            }
            configuration.worldURL = url
        }

        let server = CreatureServerClient()
        server.serverHostname = configuration.serverHost
        server.serverPort = configuration.serverPort
        server.useTLS = configuration.serverUsesTLS
        server.serverProxyHost = configuration.proxyHost
        server.apiKey = configuration.proxyAPIKey

        var clientConfiguration = HTTPClient.Configuration()
        clientConfiguration.timeout = .init(connect: .seconds(10), read: .seconds(30))
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton, configuration: clientConfiguration,
            backgroundActivityLogger: logger)
        let body = BodyService(
            configuration: configuration, server: server, client: client, logger: logger)
        let group = ServiceGroup(
            services: observabilityServices + [body],
            gracefulShutdownSignals: [.sigterm],
            cancellationSignals: [.sigint],
            logger: logger)
        try await group.run()
    }
}

enum CreatureBodyBuildInfo {
    static let version = "0.2.1"
}
