import ArgumentParser
import Common

extension CreatureCLI {

    struct Creatures: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Mess with the Creatures",
            subcommands: [List.self, Search.self, Detail.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions


        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
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

                    print("\nKnown Creatures:\n")
                    printTable(
                        creatures,
                        columns: [
                            TableColumn(title: "Name", valueProvider: { $0.name }),
                            TableColumn(title: "ID", valueProvider: { $0.id }),
                            TableColumn(
                                title: "Offset", valueProvider: { String($0.channelOffset) }),
                            TableColumn(
                                title: "Mouth Slot", valueProvider: { String($0.mouthSlot) }),
                            TableColumn(
                                title: "Audio", valueProvider: { String($0.audioChannel) }),
                            TableColumn(
                                title: "Inputs", valueProvider: { String($0.inputs.count) }),
                        ])

                    print(
                        "\n\(creatures.count) creature(s) on server at \(server.serverHostname)\n")

                case .failure(let error):
                    throw failWithMessage("Error fetching creatures: \(error.localizedDescription)")
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
                    "Searching for creature \(name) on \(globalOptions.host):\(globalOptions.port) using TLS: \(!globalOptions.insecure)"
                )
            }
        }

        struct Detail: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show details for a single creature by ID")

            @OptionGroup()
            var globalOptions: GlobalOptions

            @Argument(help: "Creature ID to show")
            var creatureId: CreatureIdentifier

            func run() async throws {
                let server = getServer(config: globalOptions)
                let result = try await server.getCreature(creatureId: creatureId)
                switch result {
                case .success(let creature):
                    print(creatureDetails(creature))
                case .failure(let error):
                    throw failWithMessage("Error fetching creature: \(error.localizedDescription)")
                }
            }
        }
    }
}
