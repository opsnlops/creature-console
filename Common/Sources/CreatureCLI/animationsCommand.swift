import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Animations: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "View and work with animations",
            subcommands: [
                Get.self, List.self, Play.self, Interrupt.self, TestAnimationEncoding.self,
                TestTrackEncoding.self, TestAnimationSaving.self,
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
}
