import ArgumentParser
import Common
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

protocol ExchangeListing: Sendable {
    func listAdHocExchanges() async -> Result<[AdHocExchange], ServerError>
}

protocol ExchangeFetching: Sendable {
    func getAdHocExchange(sessionId: String) async -> Result<AdHocExchange, ServerError>
}

protocol ExchangeAudioDownloading: Sendable {
    func downloadExchangeAudio(sessionId: String, format: ExchangeAudioFormat) async -> Result<
        CreatureServerClient.ShareableSound, ServerError
    >
}

typealias ExchangeCommandClient = ExchangeListing & ExchangeFetching & ExchangeAudioDownloading

extension CreatureServerClient: ExchangeListing {}
extension CreatureServerClient: ExchangeFetching {}
extension CreatureServerClient: ExchangeAudioDownloading {}

/// `ExchangeAudioFormat` lives in Common; make it usable as a `--format` value here.
extension ExchangeAudioFormat: ExpressibleByArgument {}

actor ExchangeCommandServerFactory {
    static let shared = ExchangeCommandServerFactory()

    private var makeServer: @Sendable (GlobalOptions) -> any ExchangeCommandClient = {
        getServer(config: $0)
    }

    func server(for options: GlobalOptions) -> any ExchangeCommandClient {
        makeServer(options)
    }

    func updateFactory(
        _ factory: @escaping @Sendable (GlobalOptions) -> any ExchangeCommandClient
    ) {
        makeServer = factory
    }

    func resetFactory() {
        makeServer = { getServer(config: $0) }
    }
}

extension CreatureCLI {

    struct Exchanges: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Inspect and download streamed ad-hoc exchanges",
            discussion:
                "An exchange is one streaming ad-hoc session — everything a creature said in one "
                + "creature-agent-driven conversation turn, stitched by the server into a single "
                + "fully-tagged file. Exchanges share the ad-hoc TTL, so the list is naturally recent.",
            subcommands: [List.self, Show.self, Download.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        static func useServerFactory(
            _ factory: @escaping @Sendable (GlobalOptions) -> any ExchangeCommandClient
        ) async {
            await ExchangeCommandServerFactory.shared.updateFactory(factory)
        }

        static func resetServerFactory() async {
            await ExchangeCommandServerFactory.shared.resetFactory()
        }

        static func makeServer(for options: GlobalOptions) async -> any ExchangeCommandClient {
            await ExchangeCommandServerFactory.shared.server(for: options)
        }

        private static func formattedDate(_ date: Date?) -> String {
            guard let date else { return "—" }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        private static func formattedDuration(_ durationMs: UInt64) -> String {
            guard durationMs > 0 else { return "—" }
            return TimeHelper.formatDuration(Double(durationMs) / 1000.0)
        }

        /// Flatten a transcript to one table-friendly line.
        private static func preview(_ transcript: String, limit: Int = 60) -> String {
            let flattened =
                transcript
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard flattened.count > limit else { return flattened }
            return String(flattened.prefix(limit - 1)) + "…"
        }

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List recent streamed exchanges, newest first"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("exchanges.list", config: globalOptions) {
                    let server = await Exchanges.makeServer(for: globalOptions)

                    switch await server.listAdHocExchanges() {
                    case .success(let exchanges):
                        if exchanges.isEmpty {
                            print("No streamed exchanges are currently available.")
                            return
                        }

                        print("\nStreamed exchanges currently on the server:\n")
                        printTable(
                            exchanges,
                            columns: [
                                TableColumn(
                                    title: "Session ID",
                                    valueProvider: { $0.sessionId }
                                ),
                                TableColumn(
                                    title: "Creature",
                                    valueProvider: { $0.creatureName }
                                ),
                                TableColumn(
                                    title: "Status",
                                    valueProvider: { $0.status.rawValue }
                                ),
                                TableColumn(
                                    title: "Duration",
                                    valueProvider: { formattedDuration($0.durationMs) }
                                ),
                                TableColumn(
                                    title: "Created",
                                    valueProvider: { formattedDate($0.createdAt) }
                                ),
                                TableColumn(
                                    title: "Transcript",
                                    valueProvider: { preview($0.transcript) }
                                ),
                            ])

                        print(
                            "\nUse 'exchanges show <session id>' for the full transcript, or "
                                + "'exchanges download <session id>' to save the audio.\n")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching exchanges: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        struct Show: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show one exchange's full transcript and parts"
            )

            @Argument(help: "The session id reported by 'exchanges list'")
            var sessionId: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("exchanges.show", config: globalOptions) {
                    let server = await Exchanges.makeServer(for: globalOptions)

                    switch await server.getAdHocExchange(sessionId: sessionId) {
                    case .success(let exchange):
                        print("")
                        if !exchange.title.isEmpty {
                            print("Title:      \(exchange.title)")
                        }
                        print("Session:    \(exchange.sessionId)")
                        print("Creature:   \(exchange.creatureName) (\(exchange.creatureId))")
                        print("Status:     \(exchange.status.rawValue)")
                        print("Duration:   \(formattedDuration(exchange.durationMs))")
                        print("Created:    \(formattedDate(exchange.createdAt))")
                        print("Finished:   \(formattedDate(exchange.finishedAt))")

                        if !exchange.transcript.isEmpty {
                            print("\nTranscript:\n")
                            print(exchange.transcript)
                        }

                        if !exchange.parts.isEmpty {
                            print("\nParts:\n")
                            printTable(
                                exchange.parts,
                                columns: [
                                    TableColumn(
                                        title: "#",
                                        valueProvider: { String($0.index) }
                                    ),
                                    TableColumn(
                                        title: "Duration",
                                        valueProvider: { formattedDuration($0.durationMs) }
                                    ),
                                    TableColumn(
                                        title: "Animation ID",
                                        valueProvider: { $0.animationId }
                                    ),
                                    TableColumn(
                                        title: "Text",
                                        valueProvider: { preview($0.text) }
                                    ),
                                ])
                        }
                        print("")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching exchange \(sessionId): \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }

        struct Download: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Download a whole exchange as one fully-tagged audio file",
                discussion:
                    "The server stitches every sentence of the session into a single file — "
                    + "MP3 (ID3-tagged: title, artist = creature, lyrics = transcript), Ogg/Opus, "
                    + "or the raw 17-channel WAV. Use --format to choose."
            )

            @Argument(help: "The session id reported by 'exchanges list'")
            var sessionId: String

            @Option(
                name: .shortAndLong,
                help:
                    "Destination file or directory. Defaults to the current directory with the server's file name."
            )
            var output: String?

            @Option(
                name: .shortAndLong,
                help: "Audio format: mp3, ogg, or wav."
            )
            var format: ExchangeAudioFormat = .mp3

            @Flag(
                name: .customLong("overwrite"),
                help: "Replace the destination file if it already exists."
            )
            var overwrite = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("exchanges.download", config: globalOptions) {
                    let server = await Exchanges.makeServer(for: globalOptions)

                    let shareable: CreatureServerClient.ShareableSound
                    switch await server.downloadExchangeAudio(sessionId: sessionId, format: format)
                    {
                    case .success(let value):
                        shareable = value
                    case .failure(let error):
                        if case .conflict = error {
                            throw failWithMessage(
                                "Exchange \(sessionId) is still streaming — try again once the "
                                    + "session finishes. (\(ServerError.detailedMessage(from: error)))"
                            )
                        }
                        throw failWithMessage(
                            "Unable to download exchange audio: \(ServerError.detailedMessage(from: error))"
                        )
                    }

                    // The server's Content-Disposition carries the friendly name
                    // ("Beaky - 2026-08-20 - <slug>.mp3"); honor it for the default.
                    let destinationURL = resolveDownloadDestination(
                        output: output, fileName: shareable.suggestedFilename)
                    try ensureDownloadDestinationWritable(destinationURL, overwrite: overwrite)

                    do {
                        try shareable.data.write(to: destinationURL, options: .atomic)
                    } catch {
                        throw failWithMessage(
                            "Failed to write exchange audio: \(error.localizedDescription)")
                    }

                    print(
                        "Downloaded exchange to \(destinationURL.path) "
                            + "(\(formatNumber(UInt64(shareable.data.count))) bytes).")
                }
            }
        }
    }
}
