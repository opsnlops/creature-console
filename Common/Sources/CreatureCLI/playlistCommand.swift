import ArgumentParser

extension CreatureCLI {

    struct Playlists: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Do things with playlists",
            subcommands: [List.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions


        struct List: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "List the playlists on the server",
                discussion:
                    "List out all of the playlists that exist on the server"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = getServer(config: globalOptions)

                let result = await server.getAllPlaylists()
                switch result {
                case .success(let playlists):

                    let headers = ["Name", "ID", "Number Of Items"]
                    var rows = [[String]]()

                    for playlist in playlists {

                        // Add this to the table
                        let row = [
                            playlist.name,
                            playlist.id,
                            String(playlist.items.count),
                        ]
                        rows.append(row)
                    }

                    print("\nOur playlists:\n")
                    printTable(headers: headers, rows: rows)

                    print(
                        "\n\(playlists.count) playlists(s) on server at \(server.serverHostname)\n")

                case .failure(let error):
                    print("Error fetching creatures: \(error)")
                }
            }

        }
    }
}
