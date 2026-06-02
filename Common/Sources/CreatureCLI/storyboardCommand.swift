import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Storyboards: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "storyboards",
            abstract: "Manage storyboards — cards of programmable tiles for live show control",
            discussion:
                "List, inspect, rename, copy, and delete the storyboards saved on the server, or create/update them from a JSON file. Storyboards are authored in the Console; this is the command-line side for quick management.",
            subcommands: [
                List.self, Detail.self, Create.self, Update.self, Rename.self, Copy.self,
                Delete.self,
            ]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        // MARK: list

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the saved storyboards on the server"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("storyboards.list", config: globalOptions) { server in
                    let result = await server.listStoryboards()
                    switch result {
                    case .success(let boards):
                        print("\nSaved Storyboards:\n")
                        printTable(
                            boards,
                            columns: [
                                TableColumn(
                                    title: "Title",
                                    valueProvider: { $0.title.isEmpty ? "(untitled)" : $0.title }),
                                TableColumn(
                                    title: "ID", valueProvider: { $0.id.uuidString.lowercased() }),
                                TableColumn(
                                    title: "Tiles", valueProvider: { String($0.tiles.count) }),
                                TableColumn(
                                    title: "Updated",
                                    valueProvider: { formatMillis($0.updatedAt) }),
                            ])
                        print(
                            "\n\(boards.count) storyboard(s) on server at \(server.serverHostname)\n"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching storyboards: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }

        // MARK: detail

        struct Detail: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show a single storyboard by ID — its tiles and actions"
            )

            @Argument(help: "Storyboard ID (UUID)")
            var storyboardId: String

            @Flag(help: "Dump the raw server JSON instead of the formatted summary")
            var json: Bool = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseUUIDArgument(storyboardId, label: "storyboard ID")
                let dumpJSON = json
                try await tracedRun("storyboards.detail", config: globalOptions) { server in
                    let result = await server.getStoryboard(id: id)
                    switch result {
                    case .success(let board):
                        print(dumpJSON ? try encodeStoryboardJSON(board) : storyboardDetails(board))
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching storyboard: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }

        // MARK: create

        struct Create: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create a new storyboard from a JSON file",
                discussion:
                    "POSTs the file as a new storyboard. The server stamps its own id and timestamps; any id in the file is ignored."
            )

            @Argument(help: "Path to the storyboard JSON file")
            var inputPath: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let board = try decodeStoryboardFile(inputPath)
                try await tracedRun("storyboards.create", config: globalOptions) { server in
                    let result = await server.createStoryboard(board)
                    switch result {
                    case .success(let saved):
                        print(
                            "✅ Created storyboard '\(saved.title)' (\(saved.id.uuidString.lowercased())) — \(saved.tiles.count) tile(s)"
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
                abstract: "Update an existing storyboard from a JSON file",
                discussion:
                    "PUTs the file to the storyboard identified by the id in the file (or --id). Preserves created_at and bumps updated_at."
            )

            @Argument(help: "Path to the storyboard JSON file")
            var inputPath: String

            @Option(
                help: "Override the storyboard ID to update (UUID); defaults to the id in the file")
            var id: String?

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                var decoded = try decodeStoryboardFile(inputPath)
                if let id {
                    decoded.id = try parseUUIDArgument(id, label: "storyboard ID")
                }
                let board = decoded
                try await tracedRun("storyboards.update", config: globalOptions) { server in
                    let result = await server.updateStoryboard(board)
                    switch result {
                    case .success(let saved):
                        print(
                            "✅ Updated storyboard '\(saved.title)' (\(saved.id.uuidString.lowercased()))"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Update failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: rename

        struct Rename: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Rename a storyboard (change its title)"
            )

            @Argument(help: "Storyboard ID (UUID)")
            var storyboardId: String

            @Argument(help: "The new title")
            var newTitle: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseUUIDArgument(storyboardId, label: "storyboard ID")
                let title = newTitle
                try await tracedRun("storyboards.rename", config: globalOptions) { server in
                    switch await server.getStoryboard(id: id) {
                    case .success(var board):
                        let oldTitle = board.title
                        board.title = title
                        switch await server.updateStoryboard(board) {
                        case .success(let saved):
                            print(
                                "✅ Renamed '\(oldTitle)' → '\(saved.title)' (\(saved.id.uuidString.lowercased()))"
                            )
                        case .failure(let error):
                            throw failWithMessage(
                                "Rename failed: \(ServerError.detailedMessage(from: error))")
                        }
                    case .failure(let error):
                        throw failWithMessage(
                            "Could not load storyboard \(id.uuidString.lowercased()): "
                                + ServerError.detailedMessage(from: error))
                    }
                }
            }
        }

        // MARK: copy

        struct Copy: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Duplicate a storyboard into a new one",
                discussion:
                    "Fetches the source and creates a fresh storyboard with the same notes and tiles. The server stamps a new id; the title defaults to '<title> (copy)'."
            )

            @Argument(help: "Storyboard ID (UUID) to copy")
            var storyboardId: String

            @Option(help: "Title for the copy (defaults to '<title> (copy)')")
            var title: String?

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseUUIDArgument(storyboardId, label: "storyboard ID")
                let overrideTitle = title
                try await tracedRun("storyboards.copy", config: globalOptions) { server in
                    switch await server.getStoryboard(id: id) {
                    case .success(let source):
                        let copyTitle = overrideTitle ?? "\(source.title) (copy)"
                        // New client-side id; the server stamps its own on create.
                        let copy = Storyboard(
                            id: UUID(), title: copyTitle, notes: source.notes, tiles: source.tiles)
                        switch await server.createStoryboard(copy) {
                        case .success(let saved):
                            print(
                                "✅ Copied '\(source.title)' → '\(saved.title)' (\(saved.id.uuidString.lowercased())) — \(saved.tiles.count) tile(s)"
                            )
                        case .failure(let error):
                            throw failWithMessage(
                                "Copy failed: \(ServerError.detailedMessage(from: error))")
                        }
                    case .failure(let error):
                        throw failWithMessage(
                            "Could not load storyboard \(id.uuidString.lowercased()): "
                                + ServerError.detailedMessage(from: error))
                    }
                }
            }
        }

        // MARK: delete

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a storyboard by ID"
            )

            @Argument(help: "Storyboard ID (UUID)")
            var storyboardId: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseUUIDArgument(storyboardId, label: "storyboard ID")
                try await tracedRun("storyboards.delete", config: globalOptions) { server in
                    switch await server.deleteStoryboard(id: id) {
                    case .success(let message):
                        print(message)
                    case .failure(let error):
                        throw failWithMessage(
                            "Delete failed: \(ServerError.detailedMessage(from: error))")
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

/// Reads and decodes a `Storyboard` JSON file. The server-shape JSON emitted by `detail --json`
/// round-trips straight back through here.
private func decodeStoryboardFile(_ path: String) throws -> Storyboard {
    let data = try readFileData(at: path)
    do {
        return try JSONDecoder().decode(Storyboard.self, from: data)
    } catch {
        throw failWithMessage("Could not parse storyboard JSON: \(error.localizedDescription)")
    }
}

/// Pretty server-shape JSON (snake_case keys, lowercase uuid) — re-importable via `create`/`update`.
private func encodeStoryboardJSON(_ board: Storyboard) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(board)
    return String(decoding: data, as: UTF8.self)
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

private func formatMillis(_ millis: Int64?) -> String {
    guard let millis else { return "—" }
    let date = Date(timeIntervalSince1970: Double(millis) / 1000.0)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}

private func storyboardDetails(_ board: Storyboard) -> String {
    var lines: [String] = []
    lines.append("Title:    \(board.title.isEmpty ? "(untitled)" : board.title)")
    lines.append("ID:       \(board.id.uuidString.lowercased())")
    if !board.notes.isEmpty {
        lines.append("Notes:    \(board.notes)")
    }
    lines.append("Created:  \(formatMillis(board.createdAt))")
    lines.append("Updated:  \(formatMillis(board.updatedAt))")
    lines.append("Tiles:    \(board.tiles.count)")
    lines.append("")
    for (index, tile) in board.tiles.enumerated() {
        let label = tile.label.isEmpty ? "(no label)" : tile.label
        let pos = String(
            format: "x=%.2f y=%.2f w=%.2f h=%.2f", tile.x, tile.y, tile.width, tile.height)
        lines.append("  [\(index + 1)] \(label)  ·  \(tile.action.typeName)")
        lines.append("      \(pos)  symbol=\(tile.sfSymbol)  tint=\(tile.tintColorHex)")
    }
    return lines.joined(separator: "\n")
}
