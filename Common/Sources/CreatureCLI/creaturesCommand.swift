import ArgumentParser

extension CreatureCLI {

    struct Creatures: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Mess with the Creatures",
            subcommands: [List.self, Search.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions


        struct List: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "List the creatures on the server",
                discussion:
                    "This command will print out a table of the creatures that the server knows about."
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = getServer(config: globalOptions)

                let result = await server.getAllCreatures()
                switch result {
                case .success(let creatures):

                    let headers = ["Name", "ID", "Offset", "Audio", "Note"]
                    var rows = [[String]]()

                    for creature in creatures {

                        // Add this to the table
                        let row = [
                            creature.name,
                            creature.id,
                            String(creature.channelOffset),
                            String(creature.audioChannel),
                            creature.notes,
                        ]
                        rows.append(row)
                    }

                    print("\nKnown Creatures:\n")
                    printTable(headers: headers, rows: rows)

                    print(
                        "\n\(creatures.count) creature(s) on server at \(server.serverHostname)\n")

                case .failure(let error):
                    print("Error fetching creatures: \(error)")
                }
            }

        }

        struct Search: AsyncParsableCommand {
            @Argument(help: "The name of the creature to search for.")
            var name: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                // Use globalOptions here
                print(
                    "Searching for creature \(name) on \(globalOptions.host):\(globalOptions.port) using TLS: \(globalOptions.useTLS)"
                )
            }
        }
    }
}
