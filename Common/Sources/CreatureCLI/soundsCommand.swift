import ArgumentParser
import Common
import Foundation

protocol SoundListing: Sendable {
    func listSounds() async -> Result<[Sound], ServerError>
}

protocol SoundPlaying: Sendable {
    func playSound(_ fileName: String) async -> Result<String, ServerError>
}

protocol LipSyncGenerating: Sendable {
    func generateLipSync(for fileName: String, allowOverwrite: Bool) async -> Result<
        JobCreatedResponse, ServerError
    >
}

typealias SoundCommandClient = SoundListing & SoundPlaying & LipSyncGenerating

extension CreatureServerClient: SoundListing {}
extension CreatureServerClient: SoundPlaying {}
extension CreatureServerClient: LipSyncGenerating {}

actor SoundCommandServerFactory {
    static let shared = SoundCommandServerFactory()

    private var makeServer: @Sendable (GlobalOptions) -> any SoundCommandClient = {
        getServer(config: $0)
    }

    func server(for options: GlobalOptions) -> any SoundCommandClient {
        makeServer(options)
    }

    func updateFactory(_ factory: @escaping @Sendable (GlobalOptions) -> any SoundCommandClient) {
        makeServer = factory
    }

    func resetFactory() {
        makeServer = { getServer(config: $0) }
    }
}

extension CreatureCLI {

    struct Sounds: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get information on the sound file subsystem",
            subcommands: [List.self, Play.self, GenerateLipSync.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        static func useServerFactory(
            _ factory: @escaping @Sendable (GlobalOptions) -> any SoundCommandClient
        ) async {
            await SoundCommandServerFactory.shared.updateFactory(factory)
        }

        static func resetServerFactory() async {
            await SoundCommandServerFactory.shared.resetFactory()
        }

        static func makeServer(for options: GlobalOptions) async -> any SoundCommandClient {
            await SoundCommandServerFactory.shared.server(for: options)
        }


        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the sound files on the server",
                discussion:
                    "This command returns a list of the sound files that the server knows about, along with their size."
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                let server = await Sounds.makeServer(for: globalOptions)

                let result = await server.listSounds()
                switch result {
                case .success(let sounds):
                    print("\nSounds available on server:\n")

                    printTable(
                        sounds,
                        columns: [
                            TableColumn(title: "Name", valueProvider: { $0.fileName }),
                            TableColumn(
                                title: "File Size",
                                valueProvider: { "\(formatNumber(UInt64($0.size))) bytes" }
                            ),
                            TableColumn(
                                title: "Has Transcript",
                                valueProvider: { $0.transcript.isEmpty ? "" : "✅" }
                            ),
                            TableColumn(
                                title: "Has Lip Sync",
                                valueProvider: { $0.lipsync.isEmpty ? "" : "✅" }
                            ),
                        ])

                    print("\n\(sounds.count) sound file(s) available on server")
                case .failure(let error):
                    throw failWithMessage(
                        "Error fetching the available sounds: \(error.localizedDescription)")
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

                let server = await Sounds.makeServer(for: globalOptions)
                let result = await server.playSound(fileName)

                switch result {
                case .success(let message):
                    print(message)
                case .failure(let error):
                    throw failWithMessage("Unable to play sound: \(error.localizedDescription)")
                }
            }
        }

        struct GenerateLipSync: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Generate Rhubarb lip sync data for a WAV sound file",
                discussion:
                    "This command triggers the server to generate a lip sync JSON file using Rhubarb. "
                    + "The operation may take 15–30 seconds and only supports .wav files."
            )

            @Argument(help: "Name of the WAV file to process on the server")
            var fileName: String

            @Flag(name: .shortAndLong, help: "Allow overwriting an existing lip sync file")
            var overwrite = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                guard fileName.lowercased().hasSuffix(".wav") else {
                    throw failWithMessage(
                        "Lip sync generation only supports WAV files. Received: \(fileName)")
                }

                print("Generating lip sync for \(fileName). This may take up to 30 seconds...\n")

                let server = await Sounds.makeServer(for: globalOptions)
                let result = await server.generateLipSync(for: fileName, allowOverwrite: overwrite)

                switch result {
                case .success(let job):
                    print("Lip sync generation job queued.")
                    print("Job ID: \(job.jobId)")
                    if !job.message.isEmpty {
                        print(job.message)
                    }
                    print("Monitor websocket job-progress/job-complete events to track status.")
                case .failure(let error):
                    throw failWithMessage(
                        "Unable to generate lip sync: \(error.localizedDescription)")
                }
            }
        }
    }
}
