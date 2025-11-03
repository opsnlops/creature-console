import ArgumentParser
import Common
import Foundation

protocol AdHocAnimationListing: Sendable {
    func listAdHocAnimations() async -> Result<[AdHocAnimationSummary], ServerError>
}

protocol AdHocAnimationFetching: Sendable {
    func getAdHocAnimation(animationId: AnimationIdentifier) async -> Result<
        Animation, ServerError
    >
}

typealias AdHocAnimationCommandClient = AdHocAnimationListing & AdHocAnimationFetching

extension CreatureServerClient: AdHocAnimationListing {}
extension CreatureServerClient: AdHocAnimationFetching {}

actor AdHocAnimationCommandServerFactory {
    static let shared = AdHocAnimationCommandServerFactory()

    private var makeServer: @Sendable (GlobalOptions) -> any AdHocAnimationCommandClient = {
        getServer(config: $0)
    }

    func server(for options: GlobalOptions) -> any AdHocAnimationCommandClient {
        makeServer(options)
    }

    func updateFactory(
        _ factory: @escaping @Sendable (GlobalOptions) -> any AdHocAnimationCommandClient
    ) {
        makeServer = factory
    }

    func resetFactory() {
        makeServer = { getServer(config: $0) }
    }
}

extension CreatureCLI {

    struct Animations: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "View and work with animations",
            discussion:
                """
                Use these commands to list, inspect, play, update, or remove animations stored on the server.
                `generate-lip-sync` queues lip sync generation for an existing animation using the server's multitrack audio.
                For generating lip sync JSON from a local WAV, use `sounds generate-lipsync-from-file`.
                """,
            subcommands: [
                Get.self, List.self, Play.self, Interrupt.self, GenerateLipSync.self, Rename.self, Delete.self,
                TestAnimationEncoding.self, TestTrackEncoding.self, TestAnimationSaving.self, AdHoc.self,
            ]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the animations for a creature",
                discussion:
                    "This command lists the animations that are found for a given creature, or at least will when I add that 😅"
            )


            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let server = getServer(config: globalOptions)

                let result = await server.listAnimations()

                switch result {
                case .success(let animations):

                    print("\nAnimations for (well. will be real):\n")
                    printTable(
                        animations,
                        columns: [
                            TableColumn(title: "Title", valueProvider: { $0.title }),
                            TableColumn(title: "ID", valueProvider: { $0.id.lowercased() }),
                            TableColumn(title: "Sound File", valueProvider: { $0.soundFile }),
                            TableColumn(
                                title: "Frames",
                                valueProvider: { formatNumber(UInt64($0.numberOfFrames)) }),
                            TableColumn(
                                title: "Multitrack",
                                valueProvider: { $0.multitrackAudio ? "✅" : "🚫" }),
                        ])

                    print(
                        "\n\(animations.count) animation(s) for creature (yes) on server at \(server.serverHostname)\n"
                    )

                case .failure(let error):
                    throw failWithMessage(
                        "Error fetching animations: \(error.localizedDescription)")
                }
            }
        }

        struct TestTrackEncoding: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Test the track encoding to JSON",
                discussion:
                    "Creates a fake track via .mock() and then prints its JSON format to the terminal"
            )


            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let mockTrack = Track.mock()

                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted

                do {
                    let jsonData = try encoder.encode(mockTrack)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        print(jsonString)
                    }
                } catch {
                    throw failWithMessage("Failed to encode Track: \(error.localizedDescription)")
                }
            }
        }

        struct TestAnimationEncoding: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Test encoding an Animation to JSON",
                discussion:
                    "Creates a fake Animation via .mock() and pretty-prints it to the console"
            )


            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let mockAnimation = Common.Animation.mock()

                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted

                do {
                    let jsonData = try encoder.encode(mockAnimation)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        print(jsonString)
                    }
                } catch {
                    throw failWithMessage(
                        "Failed to encode Animation: \(error.localizedDescription)")
                }
            }
        }

        struct TestAnimationSaving: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Test saving an animation to the server",
                discussion:
                    "Creates a fake Animation via .mock() and saves it to the server"
            )


            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let mockAnimation = Common.Animation.mock()

                // Make it obvious this is a fake one in the system
                mockAnimation.id = UUID().uuidString
                mockAnimation.metadata.title = "Fake animation created by CreatureCLI at \(Date())"

                let server = getServer(config: globalOptions)
                let result = await server.saveAnimation(animation: mockAnimation)
                switch result {

                case .success(let message):
                    print("Animation saved. Server said: \(message)")
                case .failure(let error):
                    throw failWithMessage("Unable to save animation: \(error.localizedDescription)")
                }

            }
        }

        struct AdHoc: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Inspect ad-hoc animations generated on the server",
                subcommands: [List.self, Show.self]
            )

            static func useServerFactory(
                _ factory: @escaping @Sendable (GlobalOptions) -> any AdHocAnimationCommandClient
            ) async {
                await AdHocAnimationCommandServerFactory.shared.updateFactory(factory)
            }

            static func resetServerFactory() async {
                await AdHocAnimationCommandServerFactory.shared.resetFactory()
            }

            static func makeServer(for options: GlobalOptions) async
                -> any AdHocAnimationCommandClient
            {
                await AdHocAnimationCommandServerFactory.shared.server(for: options)
            }

            private static func formattedDate(_ date: Date?) -> String {
                guard let date else { return "—" }
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }

            struct List: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "List ad-hoc animations waiting on the server"
                )

                @OptionGroup()
                var globalOptions: GlobalOptions

                func run() async throws {
                    let server = await AdHoc.makeServer(for: globalOptions)
                    let result = await server.listAdHocAnimations()

                    switch result {
                    case .success(let animations):
                        if animations.isEmpty {
                            print("No ad-hoc animations are currently available.")
                            return
                        }

                        print("\nAd-hoc animations currently cached on the server:\n")
                        printTable(
                            animations,
                            columns: [
                                TableColumn(title: "Title", valueProvider: { $0.metadata.title }),
                                TableColumn(
                                    title: "Animation ID",
                                    valueProvider: { $0.animationId.lowercased() }
                                ),
                                TableColumn(
                                    title: "Frames",
                                    valueProvider: {
                                        formatNumber(UInt64($0.metadata.numberOfFrames))
                                    }
                                ),
                                TableColumn(
                                    title: "Sound File",
                                    valueProvider: { $0.metadata.soundFile }
                                ),
                                TableColumn(
                                    title: "Created",
                                    valueProvider: { formattedDate($0.createdAt) }
                                ),
                            ])
                        print(
                            "\n\(animations.count) ad-hoc animation(s) available on server.\n"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching ad-hoc animations: \(error.localizedDescription)")
                    }
                }
            }

            struct Show: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "Display details for an ad-hoc animation"
                )

                @Argument(help: "The ad-hoc animation identifier returned by the job result")
                var animationId: AnimationIdentifier

                @OptionGroup()
                var globalOptions: GlobalOptions

                func run() async throws {
                    let server = await AdHoc.makeServer(for: globalOptions)
                    let result = await server.getAdHocAnimation(animationId: animationId)

                    switch result {
                    case .success(let animation):
                        print("\nAd-hoc Animation \(animation.metadata.id.lowercased())\n")
                        print("Title: \(animation.metadata.title)")
                        print("Sound File: \(animation.metadata.soundFile)")
                        print("Tracks: \(animation.tracks.count)")
                        print("Number of Frames: \(animation.metadata.numberOfFrames)")
                        if let created = animation.metadata.lastUpdated {
                            let stamp = AdHoc.formattedDate(created)
                            print("Last Updated: \(stamp)")
                        }
                        print("")
                    case .failure(let error):
                        throw failWithMessage(
                            "Unable to fetch ad-hoc animation: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetches an animation from the server",
            discussion:
                "This command will download an animation from the server and display information about it."
        )

        @Argument(help: "Animation ID to fetch and display")
        var animationId: AnimationIdentifier

        @OptionGroup()
        var globalOptions: GlobalOptions

        func run() async throws {

            print("attempting to fetch animation \(animationId) from the server...\n")

            let server = getServer(config: globalOptions)
            let result = await server.getAnimation(animationId: animationId)

            switch result {
            case .success(let animation):
                print("\nTitle: \(animation.metadata.title)")
                print("Tracks: \(animation.tracks.count)")
                print("Number of Frames: \(animation.metadata.numberOfFrames)")
            case .failure(let error):
                throw failWithMessage("Unable to get animation: \(error.localizedDescription)")
            }
        }
    }

    struct Play: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Plays an animation on the server",
            discussion:
                "Asks the server to play an animation that it already knows exists"
        )

        @Argument(help: "Animation ID to play")
        var animationId: AnimationIdentifier

        @OptionGroup()
        var globalOptions: GlobalOptions

        @Option(help: "Which universe?")
        var universe: UniverseIdentifier = 1

        func run() async throws {

            print("attempting to fetch animation \(animationId) from the server...\n")

            let server = getServer(config: globalOptions)
            let result = await server.playStoredAnimation(
                animationId: animationId, universe: universe)
            switch result {
            case .success(let messsage):
                print(messsage)
            case .failure(let error):
                throw failWithMessage("Unable to play animation: \(error.localizedDescription)")
            }

        }
    }

    struct Interrupt: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Interrupts current playback with an animation",
            discussion:
                "Asks the server to interrupt any currently playing playlist, play the specified animation, and optionally resume the playlist. Requires the cooperative scheduler on the server."
        )

        @Argument(help: "Animation ID to play as an interrupt")
        var animationId: AnimationIdentifier

        @OptionGroup()
        var globalOptions: GlobalOptions

        @Option(help: "Which universe?")
        var universe: UniverseIdentifier = 1

        @Flag(help: "Resume the playlist after the animation completes")
        var resume: Bool = false

        func run() async throws {

            print(
                "attempting to interrupt with animation \(animationId) on universe \(universe) (resume: \(resume))...\n"
            )

            let server = getServer(config: globalOptions)
            let result = await server.interruptWithAnimation(
                animationId: animationId, universe: universe, resumePlaylist: resume)
            switch result {
            case .success(let message):
                print(message)
            case .failure(let error):
                throw failWithMessage(
                    "Unable to interrupt with animation: \(error.localizedDescription)")
            }

        }
    }

    struct GenerateLipSync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate lip sync for a multitrack animation",
            discussion:
                "Queues a background job that extracts each creature's audio channel, runs Rhubarb lip sync, " +
                "and updates the animation's tracks in the database."
        )

        @Argument(help: "Animation ID to process")
        var animationId: AnimationIdentifier

        @OptionGroup()
        var globalOptions: GlobalOptions

        func run() async throws {

            print("queuing lip sync generation for animation \(animationId) on the server...\n")

            let server = getServer(config: globalOptions)
            let result = await server.generateLipSyncForAnimation(animationId: animationId)

            switch result {
            case .success(let job):
                print("Job queued: \(job.jobId)")
                if !job.message.isEmpty {
                    print(job.message)
                }
            case .failure(let error):
                throw failWithMessage(
                    "Unable to queue lip sync generation: \(error.localizedDescription)")
            }
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rename an animation by updating its title"
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        @Argument(help: "Animation ID to rename")
        var animationId: AnimationIdentifier

        @Argument(help: "New title for the animation")
        var newTitle: String

        func run() async throws {

            print("Renaming animation \(animationId) to '\(newTitle)'...\n")

            let server = getServer(config: globalOptions)

            let fetchResult = await server.getAnimation(animationId: animationId)
            var animation: Animation
            switch fetchResult {
            case .success(let existing):
                animation = existing
            case .failure(let error):
                throw failWithMessage("Unable to load animation: \(error.localizedDescription)")
            }

            animation.metadata.title = newTitle

            let saveResult = await server.saveAnimation(animation: animation)
            switch saveResult {
            case .success(let message):
                print(message)
            case .failure(let error):
                throw failWithMessage("Unable to save renamed animation: \(error.localizedDescription)")
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete an animation from the server",
            discussion:
                "Removes the animation document and all tracks from the database. Requires --confirm to proceed."
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        @Argument(help: "Animation ID to delete")
        var animationId: AnimationIdentifier

        @Flag(name: .customLong("confirm"), help: "Required flag to actually delete the animation.")
        var confirm: Bool = false

        func run() async throws {

            guard confirm else {
                throw failWithMessage(
                    "Refusing to delete animation without --confirm. Command aborted.")
            }

            print("Deleting animation \(animationId)...\n")

            let server = getServer(config: globalOptions)
            let result = await server.deleteAnimation(animationId: animationId)

            switch result {
            case .success(let message):
                print(message)
            case .failure(let error):
                throw failWithMessage(
                    "Unable to delete animation: \(error.localizedDescription)")
            }
        }
    }
}
