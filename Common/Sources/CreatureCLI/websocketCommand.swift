import ArgumentParser
import Foundation

extension CreatureCLI {

    struct Websocket: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "WebSocket things",
            subcommands: [Monitor.self, Inject.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        struct Monitor: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Monitor websocket messages from the server",
                discussion:
                    "This command opens up a websocket connection to the server and leaves it open for a given number of seconds. Messages that it receives will be decoded to stdout."
            )

            @Option(help: "How many seconds to leave the monitor running")
            var seconds: UInt32 = 3600

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                // Create our processor
                let processor = CLIMessageProcessor()

                let server = getServer(config: globalOptions)
                await server.connectWebsocket(processor: processor)
                print("Connected to \(server.serverHostname)! Waiting for messages...\n")

                sleep(seconds)

                _ = await server.disconnectWebsocket()
                print("\nTimeout reached! Disconnecting from the websocket.")

            }
        }


        struct Inject: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Inject messages to the server",
                discussion: "Send some messages to the server for testing purposes"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            @Option(help: "How many milliseconds to wait between messages")
            var pause: UInt32 = 1000

            @Option(help: "How many messages to inject")
            var count: UInt32 = 30


            func run() async throws {

                // Create our processor
                let processor = CLIMessageProcessor()

                let server = getServer(config: globalOptions)
                await server.connectWebsocket(processor: processor)
                print("connected to websocket")

                for i in 1...count {

                    do {
                        let result = await server.sendMessage(
                            "Hello! This is an injected message! \(i) of \(count)")
                        switch result {

                        case .failure(let error):
                            print("Error sending message: \(error.localizedDescription)")
                        default:
                            break
                        }
                    }

                    usleep(1_000 * pause)
                }

                _ = await server.disconnectWebsocket()
                print("disconnected from websocket")

            }
        }
    }
}
