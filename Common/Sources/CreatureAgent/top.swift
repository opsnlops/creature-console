import ArgumentParser
import Common
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(help: "The port to connect to")
    var port: Int = 443

    @Option(help: "The server name to connect to")
    var host: String = {
        #if DEBUG
            return "server.dev.chirpchirp.dev"
        #else
            return "server.prod.chirpchirp.dev"
        #endif
    }()

    @Flag(help: "Don't use TLS")
    var insecure: Bool = false

    @Option(help: "The proxy host to use (optional)")
    var proxyHost: String?

    @Option(help: "The API key for proxy authentication (optional)")
    var proxyApiKey: String?
}


@main
struct CreatureAgent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Listen to MQTT, call OpenAI, schedule ad-hoc speech",
        discussion:
            "Consumes MQTT topics and uses OpenAI responses to schedule ad-hoc speech animations on the Creature server.",
        version: "2.17.0",
        subcommands: [Run.self],
        defaultSubcommand: Run.self,
        helpNames: .shortAndLong
    )
}


/// Creates a fully configured server object
func getServer(config: GlobalOptions) -> CreatureServerClient {

    let server = CreatureServerClient()
    server.serverPort = config.port
    server.serverHostname = config.host
    server.useTLS = !config.insecure
    server.serverProxyHost = config.proxyHost
    server.apiKey = config.proxyApiKey

    return server
}
