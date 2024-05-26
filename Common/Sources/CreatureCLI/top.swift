import ArgumentParser
import Common
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(help: "The port to connect to")
    var port: Int = 8000

    @Option(help: "The server name to connect to")
    var host: String = "localhost"

    @Flag(help: "Use TLS")
    var useTLS: Bool = false
}


@main
struct CreatureCLI: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "A utility for interacting with the Creature Server",
        discussion: "A tool for interacting and testing the Creature Server from the command line",
        version: "2.0.10",
        subcommands: [Animations.self, Creatures.self, Sounds.self, Metrics.self, Util.self, Websocket.self],
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
    server.useTLS = config.useTLS

    return server
}


func printTable(headers: [String], rows: [[String]]) {
    let columnWidths = headers.map { header -> Int in
        rows.reduce(header.count) { max($0, $1[headers.firstIndex(of: header) ?? 0].count) }
    }

    let headerString = headers.enumerated().map { index, header -> String in
        header.padding(toLength: columnWidths[index], withPad: " ", startingAt: 0)
    }.joined(separator: " | ")

    print(headerString)
    print(String(repeating: "-", count: headerString.count))

    for row in rows {
        let rowString = row.enumerated().map { index, column -> String in
            column.padding(toLength: columnWidths[index], withPad: " ", startingAt: 0)
        }.joined(separator: " | ")
        print(rowString)
    }
}


func urlEncode(_ string: String) -> String? {
    return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
}
