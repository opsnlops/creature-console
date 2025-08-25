import ArgumentParser

extension CreatureCLI {

    struct Debug: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Debugging Helper Functions",
            subcommands: [
                InvalidateAnimationCache.self, InvalidateCreatureCache.self,
                InvalidatePlaylistCache.self, TestPlaylistUpdates.self,
            ]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        struct InvalidateAnimationCache: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Test invalidating the animation cache",
                discussion:
                    "This command tells the server to send a message to invalidate the client's animation cache"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let server = getServer(config: globalOptions)

                let result = await server.invalidateAnimationCache()
                switch result {
                case .success(let status):
                    print("Success! Server said: \(status.message)")
                case .failure(let error):
                    print("Error invalidating animation cache: \(error)")
                }
            }
        }

        struct InvalidateCreatureCache: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Test invalidating the creature cache",
                discussion:
                    "This command tells the server to send a message to invalidate the client's creature cache"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let server = getServer(config: globalOptions)

                let result = await server.invalidateCreatureCache()
                switch result {
                case .success(let status):
                    print("Success! Server said: \(status.message)")
                case .failure(let error):
                    print("Error invalidating creature cache: \(error)")
                }
            }
        }

        struct InvalidatePlaylistCache: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Test invalidating the playlist cache",
                discussion:
                    "This command tells the server to send a message to invalidate the client's playlist cache"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let server = getServer(config: globalOptions)

                let result = await server.invalidatePlaylistCache()
                switch result {
                case .success(let status):
                    print("Success! Server said: \(status.message)")
                case .failure(let error):
                    print("Error invalidating playlist cache: \(error)")
                }
            }
        }

        struct TestPlaylistUpdates: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Test sending playlist update messages",
                discussion: "This command tells the server to send a fake playlist update message"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let server = getServer(config: globalOptions)

                let result = await server.testPlaylistUpdates()
                switch result {
                case .success(let status):
                    print("Success! Server said: \(status.message)")
                case .failure(let error):
                    print("Error sending a fake playlist update request: \(error)")
                }
            }
        }
    }
}
