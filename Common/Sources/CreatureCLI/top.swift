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
}


@main
struct CreatureCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A utility for interacting with the Creature Server",
        discussion: "A tool for interacting and testing the Creature Server from the command line",
        version: "2.8.2",
        subcommands: [
            Animations.self, Creatures.self, Debug.self, Sounds.self, Metrics.self, Playlists.self,
            Util.self, Voice.self, Websocket.self,
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

    return server
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
    fputs("Error: \(message)\n", stderr)
    return .failure
}
