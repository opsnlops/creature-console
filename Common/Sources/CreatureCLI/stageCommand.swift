import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Stages: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stages",
            abstract: "Manage stages — where each creature sits and which way it faces",
            discussion: """
                A stage is the physical arrangement of the cast: each creature's position in metres \
                and its facing in degrees. The server uses it to aim heads at whoever is speaking \
                during a rendered dialog scene, and the Console uses the same document to place \
                voices in the spatial mix.

                Coordinates are relative to the listener, who sits at the origin facing -Z:
                  +x right, -x left · +y above the listener's ears, -y below · -z in front, +z behind
                Everything must fall inside ±5 m. Yaw is an absolute heading, not relative to the \
                listener: 0° faces +Z, +90° faces +X, 180° faces away.
                """,
            subcommands: [
                List.self, Detail.self, Create.self, Place.self, Remove.self, Rename.self,
                Copy.self, Animations.self, Import.self, Delete.self,
            ]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        // MARK: list

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the saved stages on the server"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("stages.list", config: globalOptions) { server in
                    switch await server.listStages() {
                    case .success(let stages):
                        print("\nSaved Stages:\n")
                        printTable(
                            stages,
                            columns: [
                                TableColumn(
                                    title: "Title",
                                    valueProvider: { $0.title.isEmpty ? "(untitled)" : $0.title }),
                                TableColumn(
                                    title: "ID", valueProvider: { $0.id.uuidString.lowercased() }),
                                TableColumn(
                                    title: "Creatures",
                                    valueProvider: { String($0.placements.count) }),
                                TableColumn(
                                    title: "Updated",
                                    valueProvider: { TimeHelper.formatEpochMillis($0.updatedAt) }),
                            ])
                        print("\n\(stages.count) stage(s) on server at \(server.serverHostname)\n")
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching stages: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: detail

        struct Detail: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show one stage — its placements, facings, and audio settings"
            )

            @Argument(help: "Stage ID (UUID)")
            var stageId: String

            @Flag(help: "Dump the raw server JSON instead of the formatted summary")
            var json: Bool = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseStageUUID(stageId)
                let dumpJSON = json
                try await tracedRun("stages.detail", config: globalOptions) { server in
                    switch await server.getStage(id: id) {
                    case .success(let stage):
                        print(dumpJSON ? try encodeStageJSON(stage) : stageDetails(stage))
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching stage: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: create

        struct Create: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create a new, empty stage",
                discussion:
                    "Creates a stage with no creatures on it. Add them with `stages place`. The server stamps the id and timestamps."
            )

            @Option(help: "Title for the new stage, e.g. 'Mainstage' or 'Travel'")
            var title: String

            @Option(help: "Free-form notes")
            var notes: String = ""

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let stage = Stage(id: UUID(), title: title, notes: notes)
                if let problem = stage.validationProblem {
                    throw failWithMessage(problem)
                }
                try await tracedRun("stages.create", config: globalOptions) { server in
                    switch await server.createStage(stage) {
                    case .success(let saved):
                        print(
                            "✅ Created stage '\(saved.title)' (\(saved.id.uuidString.lowercased()))"
                        )
                        print(
                            "   Add creatures with: stages place \(saved.id.uuidString.lowercased()) <creature>"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Create failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: place

        struct Place: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Put a creature on a stage, or move one already there",
                discussion: """
                    Adds the creature if it isn't on the stage yet, otherwise updates only the \
                    values you pass — so you can nudge a height without restating the position. \
                    The creature can be named or given by UUID.

                    Heights matter: elevation is what tells the audience which creature is being \
                    addressed. A stage with everyone at the same y throws that away.
                    """
            )

            @Argument(help: "Stage ID (UUID)")
            var stageId: String

            @Argument(help: "Creature name or ID")
            var creature: String

            // `.unconditional` so a leading '-' reads as a minus sign rather than the start of
            // another flag. Anything in front of the listener has a negative z, so negative
            // coordinates are the normal case here, not an edge case.
            @Option(
                parsing: .unconditional,
                help: "Metres to the listener's right (negative = left)")
            var x: Float?

            @Option(
                parsing: .unconditional,
                help: "Metres above the listener's ears (negative = below)")
            var y: Float?

            @Option(
                parsing: .unconditional,
                help: "Metres behind the listener (negative = in front)")
            var z: Float?

            @Option(
                parsing: .unconditional,
                help: "Facing, in degrees. 0 = +Z, +90 = +X, 180 = away from the listener")
            var yaw: Float?

            @Option(help: "RTP audio lane, 1–16 (defaults to the creature's own channel)")
            var channel: Int?

            @Option(
                parsing: .unconditional,
                help: "Linear gain for this creature in the spatial mix")
            var gain: Float?

            @Flag(help: "Mute this creature in the spatial mix")
            var muted: Bool = false

            @Flag(help: "Unmute this creature in the spatial mix")
            var unmuted: Bool = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseStageUUID(stageId)
                if muted && unmuted {
                    throw failWithMessage("Pass either --muted or --unmuted, not both.")
                }
                let creatureQuery = creature
                let (newX, newY, newZ, newYaw) = (x, y, z, yaw)
                let (newChannel, newGain) = (channel, gain)
                let mutedFlag: Bool? = muted ? true : (unmuted ? false : nil)

                try await tracedRun("stages.place", config: globalOptions) { server in
                    var stage = try await loadStage(id: id, from: server)
                    let match = try await resolveCreature(creatureQuery, from: server)

                    let isNew = stage.placement(for: match.id) == nil
                    if isNew {
                        // A brand-new placement needs a real position; defaulting silently to the
                        // origin would put the creature inside the listener's head.
                        guard let newX, let newZ else {
                            throw failWithMessage(
                                "\(match.name) isn't on this stage yet — pass at least --x and --z to place them."
                            )
                        }
                        stage.placements.append(
                            StagePlacement(
                                creatureID: match.id, creatureName: match.name,
                                audioChannel: newChannel ?? match.audioChannel,
                                x: newX, y: newY ?? 0, z: newZ, yaw: newYaw ?? 0,
                                gain: newGain ?? 1, isMuted: mutedFlag ?? false))
                    } else {
                        guard
                            let index = stage.placements.firstIndex(where: {
                                $0.creatureID == match.id
                            })
                        else {
                            throw failWithMessage("Could not find \(match.name) on the stage.")
                        }
                        // Keep the cached display name fresh in case the creature was renamed.
                        stage.placements[index].creatureName = match.name
                        if let newX { stage.placements[index].x = newX }
                        if let newY { stage.placements[index].y = newY }
                        if let newZ { stage.placements[index].z = newZ }
                        if let newYaw {
                            stage.placements[index].yaw = StagePlacement.normalizedYaw(newYaw)
                        }
                        if let newChannel { stage.placements[index].audioChannel = newChannel }
                        if let newGain { stage.placements[index].gain = newGain }
                        if let mutedFlag { stage.placements[index].isMuted = mutedFlag }
                    }

                    if let problem = stage.validationProblem {
                        throw failWithMessage(problem)
                    }

                    switch await server.updateStage(stage) {
                    case .success(let saved):
                        let verb = isNew ? "Placed" : "Moved"
                        guard let placement = saved.placement(for: match.id) else {
                            throw failWithMessage(
                                "The server saved the stage but didn't return a placement for \(match.name)."
                            )
                        }
                        print("✅ \(verb) \(match.name) on '\(saved.title)'")
                        print("   \(placementSummary(placement))")
                        print(
                            "   ⚠︎ Every animation rendered against this stage is now out of date.")
                    case .failure(let error):
                        throw failWithMessage(
                            "Update failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: remove

        struct Remove: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Take a creature off a stage"
            )

            @Argument(help: "Stage ID (UUID)")
            var stageId: String

            @Argument(help: "Creature name or ID")
            var creature: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseStageUUID(stageId)
                let creatureQuery = creature
                try await tracedRun("stages.remove", config: globalOptions) { server in
                    var stage = try await loadStage(id: id, from: server)
                    let match = try await resolveCreature(creatureQuery, from: server)
                    guard stage.placement(for: match.id) != nil else {
                        throw failWithMessage("\(match.name) isn't on '\(stage.title)'.")
                    }
                    stage.placements.removeAll { $0.creatureID == match.id }

                    switch await server.updateStage(stage) {
                    case .success(let saved):
                        print(
                            "✅ Removed \(match.name) from '\(saved.title)' — \(saved.placements.count) creature(s) left"
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
                abstract: "Rename a stage (change its title)"
            )

            @Argument(help: "Stage ID (UUID)")
            var stageId: String

            @Argument(help: "The new title")
            var newTitle: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseStageUUID(stageId)
                let title = newTitle
                try await tracedRun("stages.rename", config: globalOptions) { server in
                    var stage = try await loadStage(id: id, from: server)
                    let oldTitle = stage.title
                    stage.title = title
                    if let problem = stage.validationProblem {
                        throw failWithMessage(problem)
                    }
                    switch await server.updateStage(stage) {
                    case .success(let saved):
                        print(
                            "✅ Renamed '\(oldTitle)' → '\(saved.title)' (\(saved.id.uuidString.lowercased()))"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Rename failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: copy

        struct Copy: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Duplicate a stage into a new one",
                discussion:
                    "Handy for building a travel rendition of a mainstage arrangement — copy it, then move everyone closer together."
            )

            @Argument(help: "Stage ID (UUID) to copy")
            var stageId: String

            @Option(help: "Title for the copy (defaults to '<title> (copy)')")
            var title: String?

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseStageUUID(stageId)
                let overrideTitle = title
                try await tracedRun("stages.copy", config: globalOptions) { server in
                    let source = try await loadStage(id: id, from: server)
                    // New client-side id; the server stamps its own on create.
                    let copy = Stage(
                        id: UUID(), title: overrideTitle ?? "\(source.title) (copy)",
                        notes: source.notes, version: source.version,
                        placements: source.placements, audio: source.audio)
                    switch await server.createStage(copy) {
                    case .success(let saved):
                        print(
                            "✅ Copied '\(source.title)' → '\(saved.title)' (\(saved.id.uuidString.lowercased())) — \(saved.placements.count) creature(s)"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Copy failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: animations

        struct Animations: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the animations rendered against a stage, most out-of-date first",
                discussion:
                    "An animation is stale when it was rendered against an older version of the stage than the one stored now — move a creature and everything built on that stage needs re-rendering."
            )

            @Argument(help: "Stage ID (UUID)")
            var stageId: String

            @Flag(help: "Show only the stale animations")
            var staleOnly: Bool = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseStageUUID(stageId)
                let onlyStale = staleOnly
                try await tracedRun("stages.animations", config: globalOptions) { server in
                    switch await server.listStageAnimations(id: id) {
                    case .success(let report):
                        let items = onlyStale ? report.items.filter(\.isStale) : report.items
                        guard !items.isEmpty else {
                            print(
                                onlyStale
                                    ? "\nNothing rendered against this stage is out of date.\n"
                                    : "\nNo animations have been rendered against this stage yet.\n"
                            )
                            return
                        }
                        print("\nAnimations rendered against this stage:\n")
                        printTable(
                            items,
                            columns: [
                                TableColumn(
                                    title: "",
                                    valueProvider: { $0.isStale ? "⚠︎" : "✓" }),
                                TableColumn(
                                    title: "Title",
                                    valueProvider: { $0.title.isEmpty ? "(untitled)" : $0.title }),
                                TableColumn(
                                    title: "Animation", valueProvider: { $0.animationID }),
                                TableColumn(
                                    title: "Rendered against",
                                    valueProvider: {
                                        TimeHelper.formatEpochMillis($0.sourceStageUpdatedAt)
                                    }),
                            ])
                        print(
                            "\n\(report.stalenessSummary ?? "All \(report.count) animation(s) are current")."
                        )
                        print(
                            "Stage last edited \(TimeHelper.formatEpochMillis(report.stageUpdatedAt)).\n"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching stage animations: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }

        // MARK: import

        struct Import: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "import",
                abstract: "Upload a stage from a JSON file (restore a backup)",
                discussion:
                    "Restores a stage from JSON — e.g. one saved with `detail --json`. If a stage with the file's id still exists it's updated in place; otherwise a new one is created with a fresh server-assigned id. Use --as-new to always create a copy."
            )

            @Argument(help: "Path to the stage JSON file")
            var inputPath: String

            @Flag(help: "Always create a new stage, even if one with this id already exists")
            var asNew: Bool = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let stage = try decodeStageFile(inputPath)
                if let problem = stage.validationProblem {
                    throw failWithMessage(problem)
                }
                let forceNew = asNew
                try await tracedRun("stages.import", config: globalOptions) { server in
                    if !forceNew {
                        switch await server.getStage(id: stage.id) {
                        case .success:
                            switch await server.updateStage(stage) {
                            case .success(let saved):
                                print(
                                    "✅ Restored '\(saved.title)' in place (\(saved.id.uuidString.lowercased())) — \(saved.placements.count) creature(s)"
                                )
                                return
                            case .failure(let error):
                                throw failWithMessage(
                                    "Restore (update) failed: \(ServerError.detailedMessage(from: error))"
                                )
                            }
                        case .failure(.notFound):
                            break  // not on the server anymore — create it fresh below
                        case .failure(let error):
                            throw failWithMessage(
                                "Could not check for an existing stage: \(ServerError.detailedMessage(from: error))"
                            )
                        }
                    }

                    switch await server.createStage(stage) {
                    case .success(let saved):
                        let idNote =
                            saved.id == stage.id ? "" : " — note: the server assigned a new id"
                        print(
                            "✅ Restored '\(saved.title)' as new (\(saved.id.uuidString.lowercased())) — \(saved.placements.count) creature(s)\(idNote)"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Restore (create) failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: delete

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a stage by ID"
            )

            @Argument(help: "Stage ID (UUID)")
            var stageId: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let id = try parseStageUUID(stageId)
                try await tracedRun("stages.delete", config: globalOptions) { server in
                    switch await server.deleteStage(id: id) {
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

private func parseStageUUID(_ value: String) throws -> UUID {
    guard let uuid = UUID(uuidString: value) else {
        throw failWithMessage("'\(value)' is not a valid stage ID (expected a UUID).")
    }
    return uuid
}

private func loadStage(id: StageIdentifier, from server: CreatureServerClient) async throws -> Stage
{
    switch await server.getStage(id: id) {
    case .success(let stage):
        return stage
    case .failure(let error):
        throw failWithMessage(
            "Could not load stage \(id.uuidString.lowercased()): "
                + ServerError.detailedMessage(from: error))
    }
}

/// Resolves a creature by UUID or by name, case-insensitively. Names are how anyone actually thinks
/// about the cast, but an ambiguous one has to be an error rather than a coin flip — placing the
/// wrong bird is silent until someone watches the show.
private func resolveCreature(_ query: String, from server: CreatureServerClient) async throws
    -> Creature
{
    switch await server.getAllCreatures() {
    case .success(let creatures):
        if let exactID = creatures.first(where: {
            $0.id.caseInsensitiveCompare(query) == .orderedSame
        }) {
            return exactID
        }
        let byName = creatures.filter { $0.name.caseInsensitiveCompare(query) == .orderedSame }
        if byName.count == 1 {
            return byName[0]
        }
        if byName.count > 1 {
            let ids = byName.map(\.id).joined(separator: ", ")
            throw failWithMessage(
                "More than one creature is named '\(query)'. Use an ID instead: \(ids)")
        }
        let known = creatures.map(\.name).sorted().joined(separator: ", ")
        throw failWithMessage("No creature named '\(query)'. Known creatures: \(known)")
    case .failure(let error):
        throw failWithMessage(
            "Could not fetch the creature list: \(ServerError.detailedMessage(from: error))")
    }
}

/// Reads and decodes a `Stage` JSON file. The server-shape JSON emitted by `detail --json`
/// round-trips straight back through here.
private func decodeStageFile(_ path: String) throws -> Stage {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw failWithMessage("Input file \(url.path) does not exist.")
    }
    guard !isDirectory.boolValue else {
        throw failWithMessage("Input path \(url.path) is a directory. Provide a JSON file.")
    }
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw failWithMessage("Unable to read file: \(error.localizedDescription)")
    }
    do {
        return try JSONDecoder().decode(Stage.self, from: data)
    } catch {
        throw failWithMessage("Could not parse stage JSON: \(error.localizedDescription)")
    }
}

/// Pretty server-shape JSON (snake_case keys, lowercase uuid) — re-importable via `import`.
private func encodeStageJSON(_ stage: Stage) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(stage)
    return String(decoding: data, as: UTF8.self)
}

private func placementSummary(_ placement: StagePlacement) -> String {
    String(
        format: "x=%+.2f m  y=%+.2f m  z=%+.2f m  yaw=%+.1f°  (%@, lane %d, gain %.2f)",
        placement.x, placement.y, placement.z, placement.yaw,
        placement.isMuted ? "muted" : "unmuted", placement.audioChannel, placement.gain)
}

private func stageDetails(_ stage: Stage) -> String {
    var lines: [String] = []
    lines.append("Title:     \(stage.title.isEmpty ? "(untitled)" : stage.title)")
    lines.append("ID:        \(stage.id.uuidString.lowercased())")
    if !stage.notes.isEmpty {
        lines.append("Notes:     \(stage.notes)")
    }
    lines.append("Frame:     v\(stage.version) — listener at the origin, facing -Z, metres")
    lines.append("Created:   \(TimeHelper.formatEpochMillis(stage.createdAt))")
    lines.append("Updated:   \(TimeHelper.formatEpochMillis(stage.updatedAt))")
    lines.append("Creatures: \(stage.placements.count)")
    lines.append("")
    for placement in stage.placements.sorted(by: { $0.creatureName < $1.creatureName }) {
        let name = placement.creatureName.isEmpty ? placement.creatureID : placement.creatureName
        lines.append("  \(name)")
        lines.append("      \(placementSummary(placement))")
    }
    if !stage.placements.isEmpty {
        lines.append("")
    }
    lines.append("Audio (console-owned, stored verbatim by the server):")
    lines.append("  monitoring delay      \(stage.audio.monitoringDelayMilliseconds) ms")
    lines.append("  common playout delay  \(stage.audio.commonPlayoutDelayMilliseconds) ms")
    lines.append(String(format: "  background music gain %.2f", stage.audio.backgroundMusicGain))
    lines.append(String(format: "  reverb blend          %.2f", stage.audio.reverbBlend))
    return lines.joined(separator: "\n")
}
