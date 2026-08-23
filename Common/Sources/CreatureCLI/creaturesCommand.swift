import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Creatures: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Mess with the Creatures",
            subcommands: [
                List.self, Search.self, Detail.self, Validate.self, Import.self, Idle.self,
            ]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the creatures on the server",
                discussion:
                    "This command will print out a table of the creatures that the server knows about."
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("creatures.list", config: globalOptions) { server in
                    let result = await server.getAllCreatures()
                    switch result {
                    case .success(let creatures):

                        print("\nKnown Creatures:\n")
                        printTable(
                            creatures,
                            columns: [
                                TableColumn(title: "Name", valueProvider: { $0.name }),
                                TableColumn(title: "ID", valueProvider: { $0.id }),
                                TableColumn(
                                    title: "Offset", valueProvider: { String($0.channelOffset) }),
                                TableColumn(
                                    title: "Mouth Slot", valueProvider: { String($0.mouthSlot) }),
                                TableColumn(
                                    title: "Audio", valueProvider: { String($0.audioChannel) }),
                                TableColumn(
                                    title: "Inputs", valueProvider: { String($0.inputs.count) }),
                            ])

                        print(
                            "\n\(creatures.count) creature(s) on server at \(server.serverHostname)\n"
                        )

                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching creatures: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }

        }

        struct Search: AsyncParsableCommand {
            @Argument(help: "The name of the creature to search for.")
            var name: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                // Use globalOptions here
                print(
                    "Searching for creature \(name) on \(globalOptions.host):\(globalOptions.port) using TLS: \(!globalOptions.insecure)"
                )
            }
        }

        struct Detail: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show details for a single creature by ID",
                discussion:
                    "Prints a formatted summary, or with --json dumps the creature's complete stored config as raw JSON — every field the server persists (motors, servo settings, etc.), suitable as a backup or for re-importing. Redirect it to a file: creatures detail <id> --json > creature.json"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            @Argument(help: "Creature ID to show")
            var creatureId: CreatureIdentifier

            @Flag(help: "Dump the complete stored creature JSON instead of the formatted summary")
            var json: Bool = false

            func run() async throws {
                let dumpJSON = json
                try await tracedRun("creatures.detail", config: globalOptions) { server in
                    if dumpJSON {
                        // Raw server export — every stored field, re-importable. The typed
                        // Creature model is a trimmed view, so we never round-trip through it here.
                        switch await server.exportCreature(creatureId: creatureId) {
                        case .success(let rawJSON):
                            print(rawJSON)
                        case .failure(let error):
                            throw failWithMessage(
                                "Error exporting creature: \(ServerError.detailedMessage(from: error))"
                            )
                        }
                        return
                    }

                    let result = try await server.getCreature(creatureId: creatureId)
                    switch result {
                    case .success(let creature):
                        print(creatureDetails(creature))
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching creature: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        /// Read a creature configuration file, exactly as it sits on disk.
        ///
        /// The bytes go to the server unchanged. The Console's `Creature` model is a trimmed
        /// view of what the server stores, and an upsert replaces the whole document, so
        /// round-tripping a config through the model would quietly drop whatever it doesn't
        /// model — motors, servo settings, and anything else added since this build shipped.
        static func readCreatureConfigFile(at path: String) throws -> String {
            let inputURL = URL(fileURLWithPath: path).standardizedFileURL
            let fileManager = FileManager.default

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
            else {
                throw failWithMessage("Input file \(inputURL.path) does not exist.")
            }
            guard !isDirectory.boolValue else {
                throw failWithMessage(
                    "Input path \(inputURL.path) is a directory. Provide a JSON file.")
            }

            let rawConfig: String
            do {
                rawConfig = try String(contentsOf: inputURL, encoding: .utf8)
            } catch {
                throw failWithMessage("Unable to read JSON file: \(error.localizedDescription)")
            }

            guard !rawConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw failWithMessage("The provided JSON file is empty.")
            }

            return rawConfig
        }

        struct Import: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Upload a creature configuration JSON file to the server",
                discussion: """
                    Creates the creature if it's new, replaces its stored configuration if it \
                    already exists. The file is sent exactly as written — the server keeps the \
                    JSON it receives, so fields this build doesn't know about survive the trip.

                    Because the server replaces the whole document rather than merging, the file \
                    must be complete: anything missing from it is removed from the creature. The \
                    natural source is a `creatures detail <id> --json` dump. Try \
                    `creatures validate` first if you're unsure the file is good.
                    """
            )

            @Argument(help: "Path to the creature configuration JSON file to upload")
            var inputPath: String

            @Flag(
                name: .long,
                help: "Register the creature on a universe as well as storing its config")
            var register: Bool = false

            @Option(help: "Universe to register on. Only meaningful with --register.")
            var universe: UniverseIdentifier = 1

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let rawConfig = try Creatures.readCreatureConfigFile(at: inputPath)
                let shouldRegister = register
                let targetUniverse = universe

                try await tracedRun("creatures.import", config: globalOptions) { server in
                    let result =
                        shouldRegister
                        ? await server.registerCreature(
                            rawConfig: rawConfig, universe: targetUniverse)
                        : await server.upsertCreature(rawConfig: rawConfig)

                    switch result {
                    case .success(let creature):
                        print("✅ Stored '\(creature.name)' (\(creature.id))")
                        if shouldRegister {
                            print("   Registered on universe \(targetUniverse)")
                        }
                        print("   Inputs: \(creature.inputs.count)")
                        if let mouthInput = creature.mouthInput {
                            print("   Mouth input: \(mouthInput)")
                        }
                        if let gaze = creature.gaze, !gaze.isEmpty {
                            let axes = gaze.axes.map(\.name).joined(separator: ", ")
                            print("   Gaze axes: \(axes)")
                        }
                    case .failure(let error):
                        throw failWithMessage(
                            "Unable to store creature: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }

        struct Validate: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Validate a creature configuration JSON file",
                discussion:
                    "This command uploads a creature configuration file for validation without persisting it. It also verifies referenced animations exist and belong to the creature."
            )

            @Argument(help: "Path to the creature configuration JSON file to validate")
            var inputPath: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let rawConfig = try readCreatureConfigFile(at: inputPath)

                try await tracedRun("creatures.validate", config: globalOptions) { server in
                    let result = await server.validateCreatureConfig(rawConfig: rawConfig)
                    switch result {
                    case .success(let payload):
                        let creatureId = payload.creatureId ?? "unknown"
                        if payload.valid {
                            print("✅ Creature config is valid for creature \(creatureId)")
                        } else {
                            print("❌ Creature config is invalid for creature \(creatureId)")
                        }

                        if !payload.missingAnimationIds.isEmpty {
                            print("Missing animations:")
                            payload.missingAnimationIds.forEach { print("  - \($0)") }
                        }

                        if !payload.mismatchedAnimationIds.isEmpty {
                            print("Animations with mismatched creatures:")
                            for animationId in payload.mismatchedAnimationIds {
                                let animationResult = await server.getAnimation(
                                    animationId: animationId)
                                switch animationResult {
                                case .success(let animation):
                                    let title =
                                        animation.metadata.title.isEmpty
                                        ? "Untitled" : animation.metadata.title
                                    let creatureIds = Set(
                                        animation.tracks.compactMap { $0.creatureId })
                                    if creatureIds.count == 1, let creatureId = creatureIds.first {
                                        let name = await Self.fetchCreatureName(
                                            server: server, creatureId: creatureId)
                                        print("  - \(animationId) (\(title)) for creature \(name)")
                                    } else if creatureIds.isEmpty {
                                        print("  - \(animationId) (\(title)) for creature unknown")
                                    } else {
                                        let names = await Self.fetchCreatureNames(
                                            server: server, creatureIds: creatureIds)
                                        print(
                                            "  - \(animationId) (\(title)) for creatures \(names)")
                                    }
                                case .failure:
                                    print("  - \(animationId) (unable to fetch animation details)")
                                }
                            }
                        }

                        if !payload.errorMessages.isEmpty {
                            print("Other errors:")
                            payload.errorMessages.forEach { print("  - \($0)") }
                        }

                    case .failure(let error):
                        throw failWithMessage(
                            "Validation failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }

            private static func fetchCreatureName(
                server: CreatureServerClientProtocol, creatureId: CreatureIdentifier
            ) async -> String {
                do {
                    let result = try await server.getCreature(creatureId: creatureId)
                    switch result {
                    case .success(let creature):
                        return creature.name.isEmpty ? creatureId : creature.name
                    case .failure:
                        return creatureId
                    }
                } catch {
                    return creatureId
                }
            }

            private static func fetchCreatureNames(
                server: CreatureServerClientProtocol, creatureIds: Set<CreatureIdentifier>
            ) async -> String {
                let sorted = creatureIds.sorted()
                var names: [String] = []
                names.reserveCapacity(sorted.count)
                for creatureId in sorted {
                    let name = await fetchCreatureName(server: server, creatureId: creatureId)
                    names.append(name)
                }
                return names.joined(separator: ", ")
            }
        }

        struct Idle: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Enable or disable the idle loop for a creature"
            )

            @Argument(help: "Creature ID to update")
            var creatureId: CreatureIdentifier

            @Flag(help: "Enable idle loop")
            var enable: Bool = false

            @Flag(help: "Disable idle loop")
            var disable: Bool = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                if enable == disable {
                    throw failWithMessage("Choose exactly one of --enable or --disable.")
                }

                try await tracedRun("creatures.idle", config: globalOptions) { server in
                    let result = await server.setIdleEnabled(
                        creatureId: creatureId, enabled: enable)
                    switch result {
                    case .success(let creature):
                        let status = enable ? "enabled" : "disabled"
                        print("Idle loop \(status) for \(creature.name) (\(creature.id))")
                    case .failure(let error):
                        throw failWithMessage(
                            "Unable to update idle state: \(ServerError.detailedMessage(from: error))"
                        )
                    }
                }
            }
        }
    }
}
