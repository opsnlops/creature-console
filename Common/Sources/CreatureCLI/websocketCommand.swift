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
            enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
                case text
                case json

                static var helpDescription: String {
                    Self.allCases.map(\.rawValue).joined(separator: ", ")
                }
            }

            static let configuration = CommandConfiguration(
                abstract: "Monitor websocket messages from the server",
                discussion:
                    "This command opens up a websocket connection to the server and leaves it open for a given number of seconds. Messages that it receives will be decoded to stdout."
            )

            @Option(help: "How many seconds to leave the monitor running")
            var seconds: UInt32 = 3600

            @Option(
                name: [.customShort("H"), .customLong("hide")],
                parsing: .upToNextOption,
                help: ArgumentHelp(
                    "Hide specific message types (repeatable). Options: \(CLIMessageProcessor.MessageType.helpText)",
                    valueName: "type"
                )
            )
            var hide: [CLIMessageProcessor.MessageType] = []

            @Option(
                name: [.customShort("O"), .customLong("only")],
                parsing: .upToNextOption,
                help: ArgumentHelp(
                    "Show only the specified message types (repeatable). Options: \(CLIMessageProcessor.MessageType.helpText)",
                    valueName: "type"
                )
            )
            var only: [CLIMessageProcessor.MessageType] = []

            @Flag(name: .long, help: "Disable colored output")
            var noColor: Bool = false

            @Option(
                name: .long,
                help: ArgumentHelp("Output format (\(OutputFormat.helpDescription))", valueName: "format")
            )
            var format: OutputFormat = .text

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                // Create our processor
                let hiddenTypes = Set(hide)
                let allowedTypes = only.isEmpty ? nil : Set(only)
                let outputFormat: CLIMessageProcessor.OutputFormat = (format == .json) ? .json : .text
                let enableColor = (outputFormat == .text) && !noColor

                let processor = CLIMessageProcessor(
                    hiddenTypes: hiddenTypes,
                    allowedTypes: allowedTypes,
                    outputFormat: outputFormat,
                    useColor: enableColor
                )

                let server = getServer(config: globalOptions)
                await server.connectWebsocket(processor: processor)
                if format == .text {
                    print("Connected to \(server.serverHostname)! Waiting for messages...\n")
                }

                try await Task.sleep(for: .seconds(Int(seconds)))

                _ = await server.disconnectWebsocket()
                if format == .text {
                    print("\nTimeout reached! Disconnecting from the websocket.")
                }

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
                        _ = await server.disconnectWebsocket()
                        throw failWithMessage("Error sending frame: \(error.localizedDescription)")
                    default:
                        break
                    }

                    try await Task.sleep(for: .milliseconds(Int(frameTimeMs)))

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
                            _ = await server.disconnectWebsocket()
                            throw failWithMessage("Error sending message: \(error.localizedDescription)")
                        default:
                            break
                        }
                    }

                    try await Task.sleep(for: .milliseconds(Int(pause)))
                }

                _ = await server.disconnectWebsocket()
                print("disconnected from websocket")

            }
        }
    }


}
