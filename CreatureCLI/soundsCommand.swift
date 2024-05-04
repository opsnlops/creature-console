
import ArgumentParser
import Foundation



extension CreatureCLI {

    struct Sounds: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Mess with the Creatures",
            subcommands: [List.self, Play.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions




        struct List: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "List the sound files on the server",
                discussion: "This command returns a list of the sound files that the server knows about, along with their size."
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = getServer(config: globalOptions)

                let result = await server.listSounds()
                switch result {
                case .success(let sounds):
                    print("\nSounds available on server:\n")

                    let headers = ["Name", "File Size"]
                    var rows = [[String]]()

                    for sound in sounds {
                        // Add this to the table
                        let row = [sound.fileName, formatNumber(sound.size) + " bytes"]
                        rows.append(row)
                    }

                    printTable(headers: headers, rows: rows)

                    print("\n\(sounds.count) sound file(s) available on server")
                    case .failure(let error):
                        print("Error fetching the available sounds: \(error)")
                    }
            }
        }

        struct Play: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Play a specified sound file on the server",
                discussion: "This command sends a request to the server to play a sound file that you specify. Ensure the sound file name is correctly spelled and available on the server."
            )

            @Argument(help: "The name of the sound file to play on the server")
            var fileName: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                
                print("attempting to play \(fileName) on the server...\n")

                let server = getServer(config: globalOptions)
                let result = await server.playSound(fileName)

                switch(result) {
                case .success(let message):
                    print(message)
                case .failure(let message):
                    print("Unable to play sound: \(message)")
                }
            }
        }
    }
}

