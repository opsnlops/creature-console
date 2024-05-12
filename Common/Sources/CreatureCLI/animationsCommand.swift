import ArgumentParser
import Common

extension CreatureCLI {

    struct Animations: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "View and work with animations",
            subcommands: [List.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        struct List: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "List the animations for a creature",
                discussion:
                    "This command lists the animations that are found for a given creature, or at least will when I add that 😅"
            )


            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let server = getServer(config: globalOptions)

                let result = await server.listAnimations(creatureId: DataHelper.generateRandomId())

                switch result {
                case .success(let animations):

                    let headers = ["Title", "ID", "Sound File", "Frames", "Mutlitrack"]
                    var rows = [[String]]()

                    for metadata in animations {

                        // Add this to the table
                        let row = [
                            metadata.title,
                            metadata.id,
                            metadata.soundFile,
                            formatNumber(UInt64(metadata.numberOfFrames)),
                            metadata.multitrackAudio ? "✅" : "🚫",
                        ]
                        rows.append(row)
                    }

                    print("\nAnimations for (well. will be real):\n")
                    printTable(headers: headers, rows: rows)

                    print(
                        "\n\(animations.count) animation(s) for creature (yes) on server at \(server.serverHostname)\n"
                    )

                case .failure(let error):
                    print("Error fetching animations: \(error.localizedDescription)")
                }
            }
        }
    }
}
