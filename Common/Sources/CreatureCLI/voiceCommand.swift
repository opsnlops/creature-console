import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Voice: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Interacts with ElevenLabs.io, our voice provider",
            subcommands: [CreateSoundFile.self, List.self, SubscriptionStatus.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions


        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the available voices",
                discussion:
                    "This command lists the voices that we currently have access to at elevenlabs.io"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = getServer(config: globalOptions)

                let result = await server.listAvailableVoices()
                switch result {
                case .success(let voices):
                    print("Voices we have access to:\n")

                    let headers = ["Name", "ID"]
                    var rows = [[String]]()

                    for voice in voices {
                        // Add this to the table
                        let row = [voice.name, voice.voiceId]
                        rows.append(row)
                    }

                    printTable(headers: headers, rows: rows)

                    print("\nWe have access to \(voices.count) voice(s)")
                case .failure(let error):
                    print("Error fetching the available voices: \(error)")
                }
            }
        }


        struct SubscriptionStatus: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Get the status of our subscription",
                discussion:
                    "This command prints out the current status of our subscription for elevenlabs.io"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = getServer(config: globalOptions)

                let result = await server.getVoiceSubscriptionStatus()
                switch result {
                case .success(let subscription):

                    print("Status of our subscription for elevenlabs.io:\n")

                    print("                  Tier: \(subscription.tier)")
                    print("                Status: \(subscription.status)")
                    print(
                        "       Character Limit: \(formatNumber(UInt64(subscription.characterLimit)))"
                    )
                    print(
                        "  Characters Remaining: \(formatNumber(UInt64(subscription.characterLimit - subscription.characterCount)))\n"
                    )


                case .failure(let error):
                    print("Error fetching the status of our 11labs subscription: \(error)")
                }
            }
        }


        struct CreateSoundFile: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create sound file for a Creature",
                discussion:
                    "Creates a new sound file for a Creature, using the voice parameters that they have in the database"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions


            @Option(help: "Which Character?")
            var creatureId: CreatureIdentifier

            @Option(help: "Title of the Sound File")
            var title: String

            @Argument(help: "The text to say")
            var text: String

            func run() async throws {

                let server = getServer(config: globalOptions)

                print("\nMaking request to server! (This might take a few seconds)...\n")

                let result = await server.createCreatureSpeechSoundFile(
                    creatureId: creatureId, title: title, text: text)
                switch result {
                case .success(let speechFile):

                    print("\n...done!\n")

                    print("      Sound File: \(speechFile.soundFileName)")
                    print(" Transcript File: \(speechFile.transcriptFileName)")
                    print(
                        " Sound File Size: \(formatNumber(UInt64(speechFile.soundFileSize))) bytes\n"
                    )

                case .failure(let error):
                    print("Error creating a new sound file: \(error)")
                }
            }
        }


    }
}
