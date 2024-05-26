import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Animations: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "View and work with animations",
            subcommands: [Get.self, List.self, TestAnimationEncoding.self, TestTrackEncoding.self, TestAnimationSaving.self]
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
                            metadata.id.lowercased(),
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

        struct TestTrackEncoding: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
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
                    print("Failed to encode Track: \(error)")
                }
            }
        }

        struct TestAnimationEncoding: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
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
                    print("Failed to encode Animation: \(error)")
                }
            }
        }

        struct TestAnimationSaving: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
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
                switch(result) {

                case .success(let message):
                    print("Animation saved. Server said: \(message)")
                case .failure(let error):
                    print("Unable to save animation: \(error.localizedDescription)\n")
                }

            }
        }
    }

    struct Get: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
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
            case .failure(let message):
                print("Unable to get animation: \(message)")
            }
        }
    }
}
