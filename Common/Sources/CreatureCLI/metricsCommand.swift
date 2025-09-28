import ArgumentParser
import Foundation

extension CreatureCLI {

    struct Metrics: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Items related to metrics",
            subcommands: [ServerCounters.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions


        struct ServerCounters: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show the server's counters",
                discussion:
                    "This command requests that the server send over a copy of the current state of the internal counters and displays them."
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = getServer(config: globalOptions)

                let result = await server.getServerMetrics()
                switch result {
                case .success(let counters):
                    print("\nCurrent counters on \(server.serverHostname):\n")

                    let rows: [(String, String)] = [
                        ("Total Frames", formatNumber(counters.totalFrames)),
                        ("Events Processed", formatNumber(counters.eventsProcessed)),
                        ("Frames Streamed", formatNumber(counters.framesStreamed)),
                        ("DMX Events Processed", formatNumber(counters.dmxEventsProcessed)),
                        ("Animations Played", formatNumber(counters.animationsPlayed)),
                        ("Sounds Played", formatNumber(counters.soundsPlayed)),
                        ("Playlists Started", formatNumber(counters.playlistsStarted)),
                        ("Playlists Stopped", formatNumber(counters.playlistsStopped)),
                        ("Playlist Events Processed", formatNumber(counters.playlistsEventsProcessed)),
                        ("Playlist Status Requests", formatNumber(counters.playlistStatusRequests)),
                        ("REST API Requests", formatNumber(counters.restRequestsProcessed)),
                    ]

                    printTable(rows, columns: [
                        TableColumn(title: "Metric", valueProvider: { $0.0 }),
                        TableColumn(title: "Count", valueProvider: { $0.1 }),
                    ])

                    print("")


                case .failure(let error):
                    throw failWithMessage("Error fetching the available sounds: \(error.localizedDescription)")
                }
            }
        }

    }
}
