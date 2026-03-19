import ArgumentParser
import Common

extension CreatureCLI {

    struct Debug: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Debugging Helper Functions",
            subcommands: [
                InvalidateAnimationCache.self, InvalidateCreatureCache.self,
                InvalidatePlaylistCache.self, InvalidateSoundListCache.self,
                TestPlaylistUpdates.self,
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
                try await tracedRun("debug.invalidate-animation-cache", config: globalOptions) {
                    server in
                    let result = await server.invalidateAnimationCache()
                    switch result {
                    case .success(let status):
                        print("Success! Server said: \(status.message)")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error invalidating animation cache: \(ServerError.detailedMessage(from: error))"
                        )
                    }
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
                try await tracedRun("debug.invalidate-creature-cache", config: globalOptions) {
                    server in
                    let result = await server.invalidateCreatureCache()
                    switch result {
                    case .success(let status):
                        print("Success! Server said: \(status.message)")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error invalidating creature cache: \(ServerError.detailedMessage(from: error))"
                        )
                    }
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
                try await tracedRun("debug.invalidate-playlist-cache", config: globalOptions) {
                    server in
                    let result = await server.invalidatePlaylistCache()
                    switch result {
                    case .success(let status):
                        print("Success! Server said: \(status.message)")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error invalidating playlist cache: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }

        struct InvalidateSoundListCache: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Test invalidating the sound list cache",
                discussion:
                    "This command tells the server to send a message to invalidate the client's sound list cache"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("debug.invalidate-sound-list-cache", config: globalOptions) {
                    server in
                    let result = await server.invalidateSoundListCache()
                    switch result {
                    case .success(let status):
                        print("Success! Server said: \(status.message)")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error invalidating sound list cache: \(ServerError.detailedMessage(from: error))"
                        )
                    }
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
                try await tracedRun("debug.test-playlist-updates", config: globalOptions) {
                    server in
                    let result = await server.testPlaylistUpdates()
                    switch result {
                    case .success(let status):
                        print("Success! Server said: \(status.message)")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error sending a fake playlist update request: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }
    }
}
