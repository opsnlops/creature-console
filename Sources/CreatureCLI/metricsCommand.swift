
import ArgumentParser
import Foundation



extension CreatureCLI {

    struct Metrics: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Items related to metrics",
            subcommands: [ServerCounters.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions




        struct ServerCounters: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Show the server's counters",
                discussion: "This command requests that the server send over a copy of the current state of the internal counters and displays them."
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = getServer(config: globalOptions)

                let result = await server.getServerMetrics()
                switch result {
                case .success(let counters):
                    print("\nCurrent counters on \(server.serverHostname):\n")

                    let headers = ["Metric", "Count"]
                    var rows = [[String]]()

                    rows.append(["Total Frames", formatNumber(counters.totalFrames)])
                    rows.append(["Events Processed", formatNumber(counters.eventsProcessed)])
                    rows.append(["Frames Streamed", formatNumber(counters.framesStreamed)])
                    rows.append(["DMX Events Processed", formatNumber(counters.dmxEventsProcessed)])
                    rows.append(["Animations Played", formatNumber(counters.animationsPlayed)])
                    rows.append(["Sounds Played", formatNumber(counters.soundsPlayed)])
                    rows.append(["Playlists Started", formatNumber(counters.playlistsStarted)])
                    rows.append(["Playlists Stopped", formatNumber(counters.playlistsStopped)])
                    rows.append(["Playlist Events Processed", formatNumber(counters.playlistsEventsProcessed)])
                    rows.append(["Playlist Status Requests", formatNumber(counters.playlistStatusRequests)])
                    rows.append(["REST API Requests", formatNumber(counters.restRequestsProcessed)])

                    printTable(headers: headers, rows: rows)

                    print("")


                case .failure(let error):
                    print("Error fetching the available sounds: \(error)")
                }
            }
        }

    }
}


