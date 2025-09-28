import ArgumentParser
import Foundation

extension CreatureCLI {

    struct Sounds: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get information on the sound file subsystem",
            subcommands: [List.self, Play.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions


        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the sound files on the server",
                discussion:
                    "This command returns a list of the sound files that the server knows about, along with their size."
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = getServer(config: globalOptions)

                let result = await server.listSounds()
                switch result {
                case .success(let sounds):
                    print("\nSounds available on server:\n")

                    printTable(sounds, columns: [
                        TableColumn(title: "Name", valueProvider: { $0.fileName }),
                        TableColumn(
                            title: "File Size",
                            valueProvider: { "\(formatNumber(UInt64($0.size))) bytes" }
                        ),
                        TableColumn(
                            title: "Has Transcript",
                            valueProvider: { $0.transcript.isEmpty ? "" : "✅" }
                        ),
                    ])

                    print("\n\(sounds.count) sound file(s) available on server")
                case .failure(let error):
                    throw failWithMessage("Error fetching the available sounds: \(error.localizedDescription)")
                }
            }
        }

        struct Play: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Play a specified sound file on the server",
                discussion:
                    "This command sends a request to the server to play a sound file that you specify. Ensure the sound file name is correctly spelled and available on the server."
            )

            @Argument(help: "The name of the sound file to play on the server")
            var fileName: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                print("attempting to play \(fileName) on the server...\n")

                let server = getServer(config: globalOptions)
                let result = await server.playSound(fileName)

                switch result {
                case .success(let message):
                    print(message)
                case .failure(let error):
                    throw failWithMessage("Unable to play sound: \(error.localizedDescription)")
                }
            }
        }
    }
}
