import ArgumentParser
import Common

extension CreatureCLI {

    struct Playlists: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Do things with playlists",
            subcommands: [List.self, Start.self, Stop.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions


        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
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

                    print("\nOur playlists:\n")
                    printTable(playlists, columns: [
                        TableColumn(title: "Name", valueProvider: { $0.name }),
                        TableColumn(title: "ID", valueProvider: { $0.id }),
                        TableColumn(
                            title: "Number Of Items", valueProvider: { String($0.items.count) }),
                    ])

                    print(
                        "\n\(playlists.count) playlists(s) on server at \(server.serverHostname)\n")

                case .failure(let error):
                    throw failWithMessage("Error fetching playlists: \(error.localizedDescription)")
                }
            }

        }

        struct Start: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Starts a playlist playing",
                discussion:
                    "Asks the server to play a playlist on a given universe"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            @Argument(help: "The ID of the playlist to play")
            var playlistId: String

            @Argument(help: "The universe to start it on")
            var universe: UniverseIdentifier

            func run() async throws {

                print("attempting to start \(playlistId) on universe \(universe)...\n")

                let server = getServer(config: globalOptions)

                let result = await server.startPlayingPlaylist(
                    universe: universe, playlistId: playlistId)

                switch result {
                case .success(let message):
                    print(message)
                case .failure(let error):
                    throw failWithMessage("Unable to start playlist: \(error.localizedDescription)")
                }
            }

        }

        struct Stop: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Stops playing a playlist",
                discussion:
                    "Asks the server to stop playing a playlist on a given universe"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            @Argument(help: "The universe to stop playing on")
            var universe: UniverseIdentifier

            func run() async throws {

                print("attempting to stop playing playlists universe \(universe)...\n")

                let server = getServer(config: globalOptions)

                let result = await server.stopPlayingPlaylist(universe: universe)

                switch result {
                case .success(let message):
                    print(message)
                case .failure(let error):
                    throw failWithMessage("Unable to stop playing a playlist: \(error.localizedDescription)")
                }


            }

        }


    }
}
