import ArgumentParser
import Common
import Foundation
import Logging
import Observability
import ServiceLifecycle
import Tracing

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
struct CreatureCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A utility for interacting with the Creature Server",
        discussion: "A tool for interacting and testing the Creature Server from the command line",
        version: "2.20.0",
        subcommands: [
            Animations.self, Creatures.self, Debug.self, Metrics.self, Network.self, Playlists.self,
            Sounds.self, Util.self, Voice.self, Websocket.self,
        ],
        helpNames: .shortAndLong
    )
}


func formatNumber(_ number: UInt64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: number)) ?? ""
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

/// Run a CLI operation with OTel tracing enabled.
///
/// When `OTEL_EXPORTER_OTLP_ENDPOINT` is set, this bootstraps OTel, creates a root
/// span for the command, runs the body, and ensures traces are flushed before returning.
/// When unset, the body runs directly with no overhead.
func tracedRun(
    _ spanName: String,
    config: GlobalOptions,
    body: @Sendable () async throws -> Void
) async throws {
    let otelServices = try bootstrapObservability(serviceName: "creature-cli")

    if otelServices.isEmpty {
        try await body()
        return
    }

    // Start OTel export pipeline in background
    let exportTask = Task {
        let serviceGroup = ServiceGroup(
            services: otelServices,
            logger: Logger(label: "creature-cli.otel")
        )
        try await serviceGroup.run()
    }
    defer { exportTask.cancel() }

    try await withSpan("cli.\(spanName)") { span in
        span.attributes["cli.command"] = spanName
        try await body()
    }

    // Let the batch exporter flush before the process exits
    try? await Task.sleep(for: .seconds(2))
}

/// Convenience overload that creates a `CreatureServerClient` and passes it to the body.
func tracedRun(
    _ spanName: String,
    config: GlobalOptions,
    body: @Sendable (CreatureServerClient) async throws -> Void
) async throws {
    try await tracedRun(spanName, config: config) {
        let server = getServer(config: config)
        try await body(server)
    }
}


struct TableColumn<Value> {
    let title: String
    let valueProvider: (Value) -> String
}

func printTable<Value>(_ values: [Value], columns: [TableColumn<Value>], colorCode: String? = nil) {
    guard !columns.isEmpty else { return }

    let columnWidths = columns.map { column in
        values.reduce(column.title.count) { partialResult, value in
            max(partialResult, column.valueProvider(value).count)
        }
    }

    let header = columns.enumerated().map { index, column in
        column.title.padding(toLength: columnWidths[index], withPad: " ", startingAt: 0)
    }.joined(separator: " | ")

    let prefix = colorCode.map { "\u{001B}[\($0)m" } ?? ""
    let suffix = colorCode == nil ? "" : "\u{001B}[0m"

    print("\(prefix)\(header)\(suffix)")
    print("\(prefix)\(String(repeating: "-", count: header.count))\(suffix)")

    for value in values {
        let row = columns.enumerated().map { index, column in
            column.valueProvider(value).padding(
                toLength: columnWidths[index], withPad: " ", startingAt: 0)
        }.joined(separator: " | ")
        print("\(prefix)\(row)\(suffix)")
    }
}


func urlEncode(_ string: String) -> String? {
    return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
}

@discardableResult
func failWithMessage(_ message: String) -> ExitCode {
    if let data = "Error: \(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    return .failure
}
