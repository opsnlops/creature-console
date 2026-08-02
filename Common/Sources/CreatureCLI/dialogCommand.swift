import ArgumentParser
import Common
import Foundation

protocol DialogMusicCommandClient: JobPolling {
    func getDialogScript(id: DialogScriptIdentifier) async -> Result<DialogScript, ServerError>
    func dialogPreviewMeta(_ request: DialogPreviewRequest) async -> Result<
        CreatureServerClient.DialogPreviewMetaOutcome, ServerError
    >
    func generateDialogMusic(_ request: DialogMusicRequest) async -> Result<
        JobCreatedResponse, ServerError
    >
    func promoteDialogMusic(generationId: UUID) async -> Result<
        DialogMusicPromotionResult, ServerError
    >
    func musicCandidateURL(generationId: UUID) async -> Result<URL, ServerError>
    func downloadRawData(from url: URL) async -> Result<Data, ServerError>
}

extension CreatureServerClient: DialogMusicCommandClient {
    func musicCandidateURL(generationId: UUID) async -> Result<URL, ServerError> {
        guard let url = dialogMusicGenerationURL(generationId: generationId) else {
            return .failure(.serverError("unable to make candidate URL"))
        }
        return .success(url)
    }
}

actor DialogMusicCommandServerFactory {
    static let shared = DialogMusicCommandServerFactory()

    private var makeServer: @Sendable (GlobalOptions) -> any DialogMusicCommandClient = {
        getServer(config: $0)
    }

    func server(for options: GlobalOptions) -> any DialogMusicCommandClient {
        makeServer(options)
    }

    func updateFactory(
        _ factory: @escaping @Sendable (GlobalOptions) -> any DialogMusicCommandClient
    ) {
        makeServer = factory
    }

    func resetFactory() {
        makeServer = { getServer(config: $0) }
    }
}

extension DialogMusicGenerationMode: ExpressibleByArgument {}

extension CreatureCLI {

    struct Dialog: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Author and render multi-character dialog scenes",
            discussion:
                "Manage saved DialogScripts (CRUD + validate), author background music, render multi-track animations, and export preview audio.",
            subcommands: [
                List.self, Detail.self, Validate.self, Create.self, Update.self, Delete.self,
                Render.self, ExportMono.self, ExportMultichannel.self, Music.self,
            ]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        struct Music: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Generate, download, and accept dialog background music",
                subcommands: [Generate.self, Download.self, Promote.self]
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            static func useServerFactory(
                _ factory: @escaping @Sendable (GlobalOptions) -> any DialogMusicCommandClient
            ) async {
                await DialogMusicCommandServerFactory.shared.updateFactory(factory)
            }

            static func resetServerFactory() async {
                await DialogMusicCommandServerFactory.shared.resetFactory()
            }

            static func makeServer(
                for options: GlobalOptions
            ) async -> any DialogMusicCommandClient {
                await DialogMusicCommandServerFactory.shared.server(for: options)
            }

            struct Generate: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "Generate a temporary MP3 candidate from a full-dialog voice take",
                    discussion:
                        "The command resolves the saved script's complete voice preview, waits for music generation, and prints the temporary candidate ID. Use --output to download the MP3 immediately."
                )

                @Option(help: "Saved dialog script ID (UUID)")
                var scriptId: String

                @Option(
                    help:
                        "Specific cached full-dialog voice generation (UUID); defaults to the latest"
                )
                var dialogGenerationId: String?

                @Option(help: "Music prompt describing mood, instruments, and pacing")
                var prompt: String

                @Option(help: "Music-only tail after the dialog, in milliseconds (0...60000)")
                var durationExtensionMs: Int64 = 0

                @Option(help: "Generation style: track, loop, or ambience")
                var mode: DialogMusicGenerationMode = .track

                @Option(name: .shortAndLong, help: "Optional MP3 output path")
                var output: String?

                @Flag(help: "Replace an existing output file")
                var overwrite = false

                @OptionGroup()
                var globalOptions: GlobalOptions

                func run() async throws {
                    let scriptIdentifier = try parseUUIDArgument(scriptId, label: "script ID")
                    let requestedGeneration = try dialogGenerationId.map {
                        try parseUUIDArgument($0, label: "dialog generation ID")
                    }
                    let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanPrompt.isEmpty else {
                        throw failWithMessage("Music prompt cannot be empty.")
                    }
                    guard cleanPrompt.utf8.count <= DialogLimits.maxMusicPromptBytes else {
                        throw failWithMessage(
                            "Music prompt exceeds \(DialogLimits.maxMusicPromptBytes) UTF-8 bytes.")
                    }
                    guard (0...60_000).contains(durationExtensionMs) else {
                        throw failWithMessage(
                            "--duration-extension-ms must be between 0 and 60000.")
                    }

                    try await tracedRun("dialog.music.generate", config: globalOptions) {
                        let server = await Music.makeServer(for: globalOptions)
                        let script: DialogScript
                        switch await server.getDialogScript(id: scriptIdentifier) {
                        case .success(let value): script = value
                        case .failure(let error):
                            throw failWithMessage(
                                "Could not load dialog: \(ServerError.detailedMessage(from: error))"
                            )
                        }

                        let previewRequest = DialogPreviewRequest.fromTurns(
                            script.turns, generationId: requestedGeneration, title: script.title)
                        let meta: DialogPreviewMetaDTO
                        switch await server.dialogPreviewMeta(previewRequest) {
                        case .success(.meta(let value)):
                            meta = value
                        case .success(.queued(let job)):
                            meta = try await waitForJobResult(
                                server: server, jobId: job.jobId,
                                label: "Generating full-dialog voice take",
                                resultType: DialogPreviewMetaDTO.self)
                        case .failure(let error):
                            throw failWithMessage(
                                "Could not resolve the full-dialog voice take: \(ServerError.detailedMessage(from: error))"
                            )
                        }

                        let request = DialogMusicRequest(
                            scriptId: scriptIdentifier,
                            dialogCacheKey: meta.cacheKey,
                            dialogGenerationId: meta.generationId,
                            prompt: cleanPrompt,
                            durationExtensionMilliseconds: durationExtensionMs,
                            generationMode: mode)
                        let job: JobCreatedResponse
                        switch await server.generateDialogMusic(request) {
                        case .success(let value): job = value
                        case .failure(let error):
                            throw failWithMessage(
                                "Music generation failed: \(ServerError.detailedMessage(from: error))"
                            )
                        }

                        let candidate = try await waitForJobResult(
                            server: server, jobId: job.jobId, label: "Generating music",
                            resultType: DialogMusicGenerationResult.self)
                        print("✅ Music candidate ready")
                        print(
                            "   generation_id: \(candidate.musicGenerationId.uuidString.lowercased())"
                        )
                        print("   music: \(TimeHelper.formatDuration(candidate.durationSeconds))")
                        print(
                            "   final show: \(TimeHelper.formatDuration(candidate.finalShowDurationSeconds))"
                        )
                        print("   Candidate audio is temporary until promoted.")

                        if let output {
                            try await downloadMusicCandidate(
                                server: server, generationId: candidate.musicGenerationId,
                                output: output, overwrite: overwrite)
                        }
                    }
                }
            }

            struct Download: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "Download a temporary dialog music candidate as MP3"
                )

                @Argument(help: "Music generation ID (UUID)")
                var generationId: String

                @Option(name: .shortAndLong, help: "MP3 output path")
                var output: String

                @Flag(help: "Replace an existing output file")
                var overwrite = false

                @OptionGroup()
                var globalOptions: GlobalOptions

                func run() async throws {
                    let id = try parseUUIDArgument(generationId, label: "music generation ID")
                    try await tracedRun("dialog.music.download", config: globalOptions) {
                        let server = await Music.makeServer(for: globalOptions)
                        try await downloadMusicCandidate(
                            server: server, generationId: id, output: output,
                            overwrite: overwrite)
                    }
                }
            }

            struct Promote: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "Accept a candidate for future final renders"
                )

                @Argument(help: "Music generation ID (UUID)")
                var generationId: String

                @OptionGroup()
                var globalOptions: GlobalOptions

                func run() async throws {
                    let id = try parseUUIDArgument(generationId, label: "music generation ID")
                    try await tracedRun("dialog.music.promote", config: globalOptions) {
                        let server = await Music.makeServer(for: globalOptions)
                        switch await server.promoteDialogMusic(generationId: id) {
                        case .success(let promoted):
                            print("✅ Accepted music for final rendering")
                            print("   sound_file: \(promoted.soundFile)")
                            print(
                                "   generation_id: \(promoted.musicGenerationId.uuidString.lowercased())"
                            )
                        case .failure(let error):
                            throw failWithMessage(
                                "Could not accept music: \(ServerError.detailedMessage(from: error))"
                            )
                        }
                    }
                }
            }
        }

        // MARK: list

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the saved dialog scripts on the server"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("dialog.list", config: globalOptions) { server in
                    let result = await server.listDialogScripts()
                    switch result {
                    case .success(let scripts):
                        print("\nSaved Dialog Scripts:\n")
                        printTable(
                            scripts,
                            columns: [
                                TableColumn(
                                    title: "Title",
                                    valueProvider: { $0.title.isEmpty ? "(untitled)" : $0.title }),
                                TableColumn(
                                    title: "ID", valueProvider: { $0.id.uuidString.lowercased() }),
                                TableColumn(
                                    title: "Turns", valueProvider: { String($0.turns.count) }),
                                TableColumn(
                                    title: "Music",
                                    valueProvider: { $0.backgroundMusic == nil ? "" : "✅" }),
                                TableColumn(
                                    title: "Updated",
                                    valueProvider: { TimeHelper.formatEpochMillis($0.updatedAt) }),
                            ])
                        print(
                            "\n\(scripts.count) script(s) on server at \(server.serverHostname)\n")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching dialog scripts: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }

        // MARK: detail

        struct Detail: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show a single dialog script by ID"
            )

            @Argument(help: "Dialog script ID (UUID)")
            var scriptId: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseUUIDArgument(scriptId, label: "script ID")
                try await tracedRun("dialog.detail", config: globalOptions) { server in
                    let result = await server.getDialogScript(id: id)
                    switch result {
                    case .success(let script):
                        print(dialogScriptDetails(script))
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching dialog script: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }

        // MARK: validate

        struct Validate: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Validate a dialog script JSON file without saving it",
                discussion:
                    "Reads the file and POSTs it to the server's validate endpoint. Reports missing_creature_ids (soft warnings) and error_messages (hard blockers)."
            )

            @Argument(help: "Path to the dialog script JSON file")
            var inputPath: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let script = try decodeDialogScriptFile(inputPath)
                try await tracedRun("dialog.validate", config: globalOptions) { server in
                    let result = await server.validateDialogScript(script)
                    switch result {
                    case .success(let payload):
                        if payload.valid {
                            print("✅ Dialog script is valid (\(payload.turnCount) turn(s))")
                        } else {
                            print("❌ Dialog script is invalid (\(payload.turnCount) turn(s))")
                        }
                        if !payload.missingCreatureIds.isEmpty {
                            print("Missing creatures (soft warning, still saves):")
                            payload.missingCreatureIds.forEach { print("  - \($0)") }
                        }
                        if !payload.errorMessages.isEmpty {
                            print("Errors:")
                            payload.errorMessages.forEach { print("  - \($0)") }
                        }
                    case .failure(let error):
                        throw failWithMessage(
                            "Validation failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: create

        struct Create: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create a new dialog script from a JSON file",
                discussion:
                    "POSTs the file as a new script. The server stamps its own id and timestamps; any id in the file is ignored."
            )

            @Argument(help: "Path to the dialog script JSON file")
            var inputPath: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let script = try decodeDialogScriptFile(inputPath)
                try await tracedRun("dialog.create", config: globalOptions) { server in
                    let result = await server.createDialogScript(script)
                    switch result {
                    case .success(let saved):
                        print(
                            "✅ Created dialog '\(saved.title)' (\(saved.id.uuidString.lowercased()))"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Create failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: update

        struct Update: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Update an existing dialog script from a JSON file",
                discussion:
                    "PUTs the file to the script identified by the id in the file (or --id). Preserves created_at and bumps updated_at."
            )

            @Argument(help: "Path to the dialog script JSON file")
            var inputPath: String

            @Option(help: "Override the script ID to update (UUID); defaults to the id in the file")
            var id: String?

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                var decoded = try decodeDialogScriptFile(inputPath)
                if let id {
                    decoded.id = try parseUUIDArgument(id, label: "script ID")
                }
                let script = decoded
                try await tracedRun("dialog.update", config: globalOptions) { server in
                    let result = await server.updateDialogScript(script)
                    switch result {
                    case .success(let saved):
                        print(
                            "✅ Updated dialog '\(saved.title)' (\(saved.id.uuidString.lowercased()))"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Update failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: delete

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a dialog script by ID"
            )

            @Argument(help: "Dialog script ID (UUID)")
            var scriptId: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseUUIDArgument(scriptId, label: "script ID")
                try await tracedRun("dialog.delete", config: globalOptions) { server in
                    let result = await server.deleteDialogScript(id: id)
                    switch result {
                    case .success(let message):
                        print(message)
                    case .failure(let error):
                        throw failWithMessage(
                            "Delete failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: render

        struct Render: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Render a dialog into a multi-track animation (async job)",
                discussion:
                    "Provide exactly one of --script-id (render a saved script) or --turns-file (render an inline scene). Prints the job_id; watch progress with the `websocket` command or look for the new animation with `animations list`."
            )

            @Option(help: "ID (UUID) of a saved dialog script to render")
            var scriptId: String?

            @Option(help: "Path to a JSON file (a DialogScript or a [turn] array) to render inline")
            var turnsFile: String?

            @Option(help: "Where to store the result: 'permanent' or 'adhoc'")
            var persistence: String = "adhoc"

            @Option(help: "Optional title for the rendered animation")
            var title: String?

            @Option(help: "Render against a specific cached generation (UUID)")
            var generationId: String?

            @Flag(help: "Play immediately on the hardware once rendered")
            var autoplay: Bool = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                guard (scriptId == nil) != (turnsFile == nil) else {
                    throw failWithMessage(
                        "Provide exactly one of --script-id or --turns-file.")
                }
                let persistenceValue = try parsePersistence(persistence)
                let generation = try generationId.map {
                    try parseUUIDArgument($0, label: "generation ID")
                }

                let request: DialogRequest
                if let scriptId {
                    let id = try parseUUIDArgument(scriptId, label: "script ID")
                    request = .fromScript(
                        id, persistence: persistenceValue, autoplay: autoplay, title: title,
                        generationId: generation)
                } else {
                    let turns = try decodeTurnsFile(turnsFile!)
                    request = .fromTurns(
                        turns, persistence: persistenceValue, autoplay: autoplay, title: title,
                        generationId: generation)
                }

                try await tracedRun("dialog.render", config: globalOptions) { server in
                    let result = await server.renderDialog(request)
                    switch result {
                    case .success(let job):
                        print("✅ \(job.message)")
                        print("   job_id: \(job.jobId)")
                        print(
                            "   Watch progress: creature-cli websocket  (filter on this job_id)")
                    case .failure(let error):
                        throw failWithMessage(
                            "Render failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: export-mono

        struct ExportMono: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "export-mono",
                abstract: "Export the mono preview WAV for a scene to a file"
            )

            @Option(help: "ID (UUID) of a saved dialog script")
            var scriptId: String?

            @Option(help: "Path to a JSON file (a DialogScript or a [turn] array)")
            var turnsFile: String?

            @Option(help: "Render against a specific cached generation (UUID)")
            var generationId: String?

            @Option(name: .shortAndLong, help: "Output WAV path")
            var output: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let scriptId = scriptId
                let turnsFile = turnsFile
                let generationId = generationId
                let output = output
                try await tracedRun("dialog.export-mono", config: globalOptions) { server in
                    let request = try await buildPreviewRequest(
                        server: server, scriptId: scriptId, turnsFile: turnsFile,
                        generationId: generationId)
                    let meta: DialogPreviewMetaDTO
                    switch await server.dialogPreviewMeta(request) {
                    case .success(.meta(let dto)):
                        meta = dto
                    case .success(.queued(let job)):
                        // Fresh generation runs as a job now (server 3.23.0+) — poll it.
                        meta = try await waitForJobResult(
                            server: server, jobId: job.jobId, label: "Generating voices",
                            resultType: DialogPreviewMetaDTO.self)
                    case .failure(let error):
                        throw failWithMessage(
                            "Could not resolve the preview: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                    guard let url = server.makeAbsoluteURL(fromRelativePath: meta.audioUrl) else {
                        throw failWithMessage("Could not resolve the mono preview audio URL.")
                    }
                    let dataResult = await server.downloadRawData(from: url)
                    switch dataResult {
                    case .success(let data):
                        try writeWav(data, to: output)
                        print("✅ Wrote mono WAV (\(data.count) bytes) to \(output)")
                    case .failure(let error):
                        throw failWithMessage(
                            "Mono export failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: export-multichannel

        struct ExportMultichannel: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "export-multichannel",
                abstract: "Export the 17-channel WAV for a scene to a file (for Audacity)"
            )

            @Option(help: "ID (UUID) of a saved dialog script")
            var scriptId: String?

            @Option(help: "Path to a JSON file (a DialogScript or a [turn] array)")
            var turnsFile: String?

            @Option(help: "Render against a specific cached generation (UUID)")
            var generationId: String?

            @Option(name: .shortAndLong, help: "Output WAV path")
            var output: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let scriptId = scriptId
                let turnsFile = turnsFile
                let generationId = generationId
                let output = output
                try await tracedRun("dialog.export-multichannel", config: globalOptions) {
                    server in
                    let request = try await buildPreviewRequest(
                        server: server, scriptId: scriptId, turnsFile: turnsFile,
                        generationId: generationId)
                    // Always a job now (server 3.23.0) — the assembled WAV lands in the
                    // ad-hoc sound bucket and we download it from there.
                    switch await server.dialogPreviewMultichannel(request) {
                    case .success(let job):
                        let export = try await waitForJobResult(
                            server: server, jobId: job.jobId, label: "Assembling 17-channel WAV",
                            resultType: DialogPreviewExportResult.self)
                        guard case .success(let url) = server.getAdHocSoundURL(export.fileName)
                        else {
                            throw failWithMessage("Could not build the exported WAV's URL.")
                        }
                        switch await server.downloadRawData(from: url) {
                        case .success(let data):
                            try writeWav(data, to: output)
                            print("✅ Wrote 17-channel WAV (\(data.count) bytes) to \(output)")
                        case .failure(let error):
                            throw failWithMessage(
                                "Multichannel download failed: \(ServerError.detailedMessage(from: error))"
                            )
                        }
                    case .failure(let error):
                        throw failWithMessage(
                            "Multichannel export failed: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

private func parseUUIDArgument(_ value: String, label: String) throws -> UUID {
    guard let uuid = UUID(uuidString: value) else {
        throw failWithMessage("'\(value)' is not a valid \(label) (expected a UUID).")
    }
    return uuid
}

private func parsePersistence(_ value: String) throws -> DialogPersistence {
    guard let p = DialogPersistence(rawValue: value.lowercased()) else {
        throw failWithMessage("persistence must be 'permanent' or 'adhoc' (got '\(value)').")
    }
    return p
}

/// Reads and decodes a `DialogScript` JSON file. Defaults missing optional fields so a
/// hand-written file with just `title` + `turns` works.
private func decodeDialogScriptFile(_ path: String) throws -> DialogScript {
    let data = try readFileData(at: path)
    do {
        return try JSONDecoder().decode(DialogScript.self, from: data)
    } catch {
        throw failWithMessage("Could not parse dialog script JSON: \(error.localizedDescription)")
    }
}

/// Reads turns from a file that is either a full `DialogScript` or a bare `[turn]` array.
private func decodeTurnsFile(_ path: String) throws -> [DialogScriptTurn] {
    let data = try readFileData(at: path)
    if let script = try? JSONDecoder().decode(DialogScript.self, from: data) {
        return script.turns
    }
    if let turns = try? JSONDecoder().decode([DialogScriptTurn].self, from: data) {
        return turns
    }
    throw failWithMessage(
        "Could not parse turns from \(path) (expected a DialogScript or a [turn] array).")
}

/// Builds a preview request from either a saved script id (fetched for its turns) or a turns
/// file. The preview endpoints are turns-only — there is no `script_id` on the wire — so a
/// `--script-id` is resolved to its turns here via `getDialogScript`.
private func buildPreviewRequest(
    server: CreatureServerClient, scriptId: String?, turnsFile: String?, generationId: String?
) async throws -> DialogPreviewRequest {
    guard (scriptId == nil) != (turnsFile == nil) else {
        throw failWithMessage("Provide exactly one of --script-id or --turns-file.")
    }
    let generation = try generationId.map { try parseUUIDArgument($0, label: "generation ID") }
    let turns: [DialogScriptTurn]
    if let scriptId {
        let id = try parseUUIDArgument(scriptId, label: "script ID")
        switch await server.getDialogScript(id: id) {
        case .success(let script):
            turns = script.turns
        case .failure(let error):
            throw failWithMessage(
                "Could not load script \(id.uuidString.lowercased()): "
                    + ServerError.detailedMessage(from: error))
        }
    } else {
        turns = try decodeTurnsFile(turnsFile!)
    }
    return .fromTurns(turns, generationId: generation)
}

private func readFileData(at path: String) throws -> Data {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw failWithMessage("Input file \(url.path) does not exist.")
    }
    guard !isDirectory.boolValue else {
        throw failWithMessage("Input path \(url.path) is a directory. Provide a JSON file.")
    }
    do {
        return try Data(contentsOf: url)
    } catch {
        throw failWithMessage("Unable to read file: \(error.localizedDescription)")
    }
}

private func writeWav(_ data: Data, to path: String) throws {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    do {
        try data.write(to: url, options: .atomic)
    } catch {
        throw failWithMessage("Unable to write WAV to \(url.path): \(error.localizedDescription)")
    }
}

private func downloadMusicCandidate(
    server: any DialogMusicCommandClient, generationId: UUID, output: String, overwrite: Bool
) async throws {
    guard output.lowercased().hasSuffix(".mp3") else {
        throw failWithMessage("Dialog music candidates are MP3-only; --output must end in .mp3.")
    }
    let destination = URL(fileURLWithPath: output).standardizedFileURL
    if FileManager.default.fileExists(atPath: destination.path), !overwrite {
        throw failWithMessage(
            "Destination \(destination.path) already exists. Use --overwrite to replace it.")
    }
    let url: URL
    switch await server.musicCandidateURL(generationId: generationId) {
    case .success(let value): url = value
    case .failure(let error):
        throw failWithMessage(
            "Could not build the candidate URL: \(ServerError.detailedMessage(from: error))")
    }
    switch await server.downloadRawData(from: url) {
    case .success(let data):
        do {
            try data.write(to: destination, options: .atomic)
            print("✅ Wrote candidate MP3 (\(data.count) bytes) to \(destination.path)")
        } catch {
            throw failWithMessage(
                "Unable to write MP3 to \(destination.path): \(error.localizedDescription)")
        }
    case .failure(.notFound):
        throw failWithMessage("That temporary music candidate has expired. Generate it again.")
    case .failure(let error):
        throw failWithMessage(
            "Candidate download failed: \(ServerError.detailedMessage(from: error))")
    }
}

private func dialogScriptDetails(_ script: DialogScript) -> String {
    var lines: [String] = []
    lines.append("Title:    \(script.title)")
    lines.append("ID:       \(script.id.uuidString.lowercased())")
    if !script.notes.isEmpty {
        lines.append("Notes:    \(script.notes)")
    }
    lines.append("Created:  \(TimeHelper.formatEpochMillis(script.createdAt))")
    lines.append("Updated:  \(TimeHelper.formatEpochMillis(script.updatedAt))")
    lines.append("Turns:    \(script.turns.count)")
    if let music = script.backgroundMusic {
        lines.append("Music:    \(music.soundFile)")
        lines.append("Prompt:   \(music.prompt)")
    }
    lines.append("")
    for (index, turn) in script.turns.enumerated() {
        lines.append("  [\(index + 1)] \(turn.creatureId)")
        lines.append("      \(turn.text)")
    }
    return lines.joined(separator: "\n")
}
