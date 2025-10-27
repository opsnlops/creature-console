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

protocol AdHocSoundListing: Sendable {
    func listAdHocSounds() async -> Result<[AdHocSoundEntry], ServerError>
}

@preconcurrency protocol AdHocSoundURLProviding: Sendable {
    func adHocSoundURL(for fileName: String) async -> Result<URL, ServerError>
}

@preconcurrency protocol SoundURLProviding: Sendable {
    func soundURL(for fileName: String) async -> Result<URL, ServerError>
}

typealias SoundCommandClient = SoundListing & SoundPlaying & LipSyncGenerating & AdHocSoundListing
    & AdHocSoundURLProviding & SoundURLProviding

extension CreatureServerClient: SoundListing {}
extension CreatureServerClient: SoundPlaying {}
extension CreatureServerClient: LipSyncGenerating {}
extension CreatureServerClient: AdHocSoundListing {}
extension CreatureServerClient: AdHocSoundURLProviding {
    public func adHocSoundURL(for fileName: String) async -> Result<URL, ServerError> {
        getAdHocSoundURL(fileName)
    }
}
extension CreatureServerClient: SoundURLProviding {
    public func soundURL(for fileName: String) async -> Result<URL, ServerError> {
        getSoundURL(fileName)
    }
}

actor SoundDownloadHandlerStore {
    typealias Handler = @Sendable (URLRequest, URL) async throws -> URL

    static let shared = SoundDownloadHandlerStore()

    private var handler: Handler = SoundDownloadHandlerStore.defaultHandler

    private static func defaultHandler(request: URLRequest, destination: URL) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(for: request)
        let fm = FileManager.default

        let parentDirectory = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        try fm.moveItem(at: tempURL, to: destination)
        return destination
    }

    func download(request: URLRequest, destination: URL) async throws -> URL {
        try await handler(request, destination)
    }

    func updateHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func resetHandler() {
        handler = SoundDownloadHandlerStore.defaultHandler
    }
}

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
            subcommands: [List.self, Play.self, GenerateLipSync.self, Download.self, AdHoc.self]
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

        struct Download: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Download a sound file locally"
            )

            @Argument(help: "Name of the sound file to download")
            var fileName: String

            @Option(
                name: .shortAndLong,
                help:
                    "Destination file or directory. Defaults to the current directory with the server file name."
            )
            var output: String?

            @Flag(
                name: .customLong("overwrite"),
                help: "Replace the destination file if it already exists."
            )
            var overwrite = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await Sounds.performDownload(
                    requestedName: fileName,
                    defaultFileName: fileName,
                    output: output,
                    overwrite: overwrite,
                    globalOptions: globalOptions
                ) { server in
                    await server.soundURL(for: fileName)
                }
            }
        }

        struct AdHoc: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Inspect and download ad-hoc/generated sounds",
                subcommands: [List.self, Download.self]
            )

            private static func formattedDate(_ date: Date?) -> String {
                guard let date else { return "—" }
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }

            struct List: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "List ad-hoc/generated sounds on the server"
                )

                @OptionGroup()
                var globalOptions: GlobalOptions

                func run() async throws {
                    let server = await Sounds.makeServer(for: globalOptions)
                    let result = await server.listAdHocSounds()

                    switch result {
                    case .success(let entries):
                        if entries.isEmpty {
                            print("No ad-hoc sounds are currently available.")
                            return
                        }

                        print("\nAd-hoc sounds currently cached on the server:\n")
                        printTable(
                            entries,
                            columns: [
                                TableColumn(
                                    title: "Animation ID",
                                    valueProvider: { $0.animationId.lowercased() }
                                ),
                                TableColumn(
                                    title: "Sound File",
                                    valueProvider: { $0.sound.fileName }
                                ),
                                TableColumn(
                                    title: "Size",
                                    valueProvider: {
                                        "\(formatNumber(UInt64($0.sound.size))) bytes"
                                    }
                                ),
                                TableColumn(
                                    title: "Transcript",
                                    valueProvider: { $0.sound.transcript.isEmpty ? "" : "✅" }
                                ),
                                TableColumn(
                                    title: "Created",
                                    valueProvider: { formattedDate($0.createdAt) }
                                ),
                                TableColumn(
                                    title: "Download Path",
                                    valueProvider: { $0.soundFilePath }
                                ),
                            ])

                        print(
                            "\nUse 'sounds ad-hoc download <download path>' to grab a WAV locally.\n"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching ad-hoc sounds: \(error.localizedDescription)")
                    }
                }
            }

            struct Download: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "Download an ad-hoc sound file locally"
                )

                @Argument(
                    help:
                        "Sound file path reported by 'sounds ad-hoc list' (e.g., ad-hoc/12345.wav)"
                )
                var soundFilePath: String

                @Option(
                    name: .shortAndLong,
                    help:
                        "Destination file or directory. Defaults to the current directory with the server file name."
                )
                var output: String?

                @Flag(
                    name: .customLong("overwrite"),
                    help: "Replace the destination file if it already exists."
                )
                var overwrite = false

                @OptionGroup()
                var globalOptions: GlobalOptions

                func run() async throws {
                    let fileName = (soundFilePath as NSString).lastPathComponent
                    try await Sounds.performDownload(
                        requestedName: soundFilePath,
                        defaultFileName: fileName,
                        output: output,
                        overwrite: overwrite,
                        globalOptions: globalOptions
                    ) { server in
                        await server.adHocSoundURL(for: soundFilePath)
                    }
                }
            }
        }
    }
}

extension CreatureCLI.Sounds {

    fileprivate static func performDownload(
        requestedName: String,
        defaultFileName: String,
        output: String?,
        overwrite: Bool,
        globalOptions: GlobalOptions,
        remoteURLProvider: @escaping (any SoundCommandClient) async -> Result<URL, ServerError>
    ) async throws {
        let destinationURL = resolveDestinationURL(output: output, fileName: defaultFileName)
        try ensureDestinationWritable(destinationURL, overwrite: overwrite)

        let server = await makeServer(for: globalOptions)
        let remoteURL: URL
        switch await remoteURLProvider(server) {
        case .success(let url):
            remoteURL = url
        case .failure(let error):
            throw failWithMessage(
                "Unable to determine download URL: \(error.localizedDescription)")
        }

        let request = configuredRequest(for: server, url: remoteURL)

        do {
            let savedURL = try await SoundDownloadHandlerStore.shared.download(
                request: request, destination: destinationURL)
            printDownloadSuccess(at: savedURL)
        } catch {
            throw failWithMessage(
                "Failed to download sound: \(error.localizedDescription)")
        }
    }

    fileprivate static func resolveDestinationURL(output: String?, fileName: String) -> URL {
        let fileManager = FileManager.default

        if let output {
            var outputURL = URL(fileURLWithPath: output)

            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                return outputURL.appendingPathComponent(fileName)
            }

            if output.hasSuffix("/") {
                outputURL.appendPathComponent(fileName)
                return outputURL
            }

            return outputURL
        } else {
            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            return cwd.appendingPathComponent(fileName)
        }
    }

    fileprivate static func ensureDestinationWritable(_ url: URL, overwrite: Bool) throws {
        let fileManager = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: url.path) {
            guard overwrite else {
                throw failWithMessage(
                    "Destination \(url.path) already exists. Use --overwrite to replace it.")
            }
            try fileManager.removeItem(at: url)
        }
    }

    fileprivate static func configuredRequest(
        for server: any SoundCommandClient,
        url: URL
    ) -> URLRequest {
        if let concreteServer = server as? CreatureServerClient {
            return concreteServer.createConfiguredURLRequest(for: url)
        } else {
            return URLRequest(url: url)
        }
    }

    fileprivate static func printDownloadSuccess(at url: URL) {
        let fm = FileManager.default
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? NSNumber {
            print("Downloaded sound to \(url.path) (\(formatNumber(size.uint64Value)) bytes).")
        } else {
            print("Downloaded sound to \(url.path).")
        }
    }
}
