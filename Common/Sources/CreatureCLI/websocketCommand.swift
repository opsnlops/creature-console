import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Websocket: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "WebSocket things",
            subcommands: [Monitor.self, Inject.self, StreamTest.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        struct Monitor: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
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


        struct StreamTest: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Generate fake streaming frames",
                discussion:
                    "Generates fake streamed frames and send them to the server. This will use an actual creature, so beware! 😅"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            @Option(help: "How many fake frames to send?")
            var number: Int = 100

            @Option(help: "How many milliseconds per frame?")
            var frameTimeMs: UInt32 = 20

            @Option(help: "Which universe?")
            var universe: UniverseIdentifier = 1

            @Option(help: "How many joints to fake?")
            var joints: Int = 6

            @Argument(help: "The ID of a creature to send fake frames to")
            var creatureId: CreatureIdentifier

            func run() async throws {

                // Create our processor
                let processor = CLIMessageProcessor()

                let server = getServer(config: globalOptions)
                await server.connectWebsocket(processor: processor)
                print("connected to websocket")

                let fakeData = generateBase64TestData(count: number, length: joints)

                var counter = 0
                for data in fakeData {

                    // Make a fake frame
                    let frame = StreamFrameData(
                        ceatureId: creatureId, universe: universe, data: data)

                    counter += 1
                    print("Sending frame \(counter)...")

                    let result = await server.streamFrame(streamFrameData: frame)
                    switch result {
                    case .failure(let error):
                        print("Error sending frame: \(error.localizedDescription)")
                    default:
                        break
                    }

                    usleep(1_000 * frameTimeMs)

                }

                _ = await server.disconnectWebsocket()
            }

            /// A function to make the fake data for testing
            func generateBase64TestData(count: Int, length: Int) -> [String] {
                var testDataArray = [String]()

                // Generate the first row with random bytes
                var firstRow = [UInt8]()
                for _ in 0..<length {
                    firstRow.append(UInt8.random(in: 0...255))
                }

                // Convert the first row to a base64 string and add it to the array
                let firstRowData = Data(firstRow)
                let firstRowBase64String = firstRowData.base64EncodedString()
                testDataArray.append(firstRowBase64String)

                // Generate subsequent rows by incrementing the previous row's values
                for _ in 1..<count {
                    var newRow = [UInt8]()
                    for byte in firstRow {
                        newRow.append(byte &+ 1)
                    }
                    firstRow = newRow  // Update firstRow to be the newRow for the next iteration

                    let newRowData = Data(newRow)
                    let newRowBase64String = newRowData.base64EncodedString()
                    testDataArray.append(newRowBase64String)
                }

                return testDataArray
            }

        }

        struct Inject: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
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

                        let clientMessage = String(
                            "Hello! This is an injected message! \(i) of \(count)")

                        // Create a notice to send to the server
                        var notice = Common.Notice()
                        notice.message = clientMessage
                        notice.timestamp = Date()

                        // Use WebSocketMessageBuilder to create the JSON message
                        let noticeJSON = try WebSocketMessageBuilder.createMessage(
                            type: .notice, payload: notice)

                        // Send the encoded JSON message
                        let result = await server.sendMessage(noticeJSON)

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
