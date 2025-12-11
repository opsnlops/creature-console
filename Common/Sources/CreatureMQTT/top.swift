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


struct MQTTOptions: ParsableArguments {
    @Option(name: .long, help: "MQTT broker host")
    var mqttHost: String = "home.opsnlops.io"

    @Option(name: .long, help: "MQTT broker port")
    var mqttPort: Int = 1883

    @Flag(name: .long, help: "Connect to MQTT over TLS")
    var mqttTLS: Bool = false

    @Option(name: .long, help: "MQTT username (optional)")
    var mqttUsername: String?

    @Option(name: .long, help: "MQTT password (optional)")
    var mqttPassword: String?

    @Option(
        name: .long,
        help: "MQTT client identifier (defaults to a generated creature-mqtt value)")
    var clientId: String?

    @Option(name: .long, help: "MQTT topic prefix for published messages")
    var topicPrefix: String = "creatures"

    @Option(name: .long, help: "MQTT keep-alive value in seconds")
    var mqttKeepAlive: Int = 60

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: "Retain MQTT messages (use --no-retain to disable)")
    var retain: Bool = true
}


@main
struct CreatureMQTT: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Bridge Creature websocket events into MQTT",
        discussion:
            "Subscribes to the Creature websocket API and republishes incoming messages to an MQTT broker for Home Assistant.",
        version: "2.15.2",
        subcommands: [Bridge.self],
        defaultSubcommand: Bridge.self,
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
