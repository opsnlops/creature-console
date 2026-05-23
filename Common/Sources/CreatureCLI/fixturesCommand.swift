import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Fixtures: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage DMX fixtures on the server",
            subcommands: [
                List.self, Detail.self, Validate.self, Upsert.self, Delete.self,
                Universe.self, Trigger.self, Live.self,
            ]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        // MARK: list

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the DMX fixtures on the server"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("fixtures.list", config: globalOptions) { server in
                    let result = await server.getAllFixtures()
                    switch result {
                    case .success(let fixtures):
                        print("\nKnown DMX Fixtures:\n")
                        printTable(
                            fixtures,
                            columns: [
                                TableColumn(title: "Name", valueProvider: { $0.name }),
                                TableColumn(title: "ID", valueProvider: { $0.id }),
                                TableColumn(
                                    title: "Type",
                                    valueProvider: { $0.type.rawValue }),
                                TableColumn(
                                    title: "Universe",
                                    valueProvider: {
                                        $0.assignedUniverse.map(String.init) ?? "—"
                                    }),
                                TableColumn(
                                    title: "Offset",
                                    valueProvider: { String($0.channelOffset) }),
                                TableColumn(
                                    title: "Channels",
                                    valueProvider: { String($0.channels.count) }),
                                TableColumn(
                                    title: "Patterns",
                                    valueProvider: { String($0.patterns.count) }),
                                TableColumn(
                                    title: "Bindings",
                                    valueProvider: { String($0.bindings.count) }),
                            ])

                        print(
                            "\n\(fixtures.count) fixture(s) on server at \(server.serverHostname)\n"
                        )

                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching fixtures: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: detail

        struct Detail: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show details for a single DMX fixture by ID"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            @Argument(help: "Fixture ID (UUID) to show")
            var fixtureId: DmxFixtureIdentifier

            func run() async throws {
                try await tracedRun("fixtures.detail", config: globalOptions) { server in
                    let result = await server.getFixture(id: fixtureId)
                    switch result {
                    case .success(let fixture):
                        print(fixtureDetails(fixture))
                    case .failure(let error):
                        throw failWithMessage(
                            "Error fetching fixture: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: validate

        struct Validate: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Validate a DMX fixture JSON file without saving it",
                discussion:
                    "Reads the file from disk and POSTs it to the server's validate endpoint. Reports missing_creature_ids (soft warnings) and error_messages (hard blockers)."
            )

            @Argument(help: "Path to the fixture JSON file to validate")
            var inputPath: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let rawJson = try readJsonFile(at: inputPath)

                try await tracedRun("fixtures.validate", config: globalOptions) { server in
                    let result = await server.validateFixture(rawJson: rawJson)
                    switch result {
                    case .success(let payload):
                        let fixtureId = payload.fixtureId ?? "unknown"
                        if payload.valid {
                            print("✅ Fixture config is valid for fixture \(fixtureId)")
                        } else {
                            print("❌ Fixture config is invalid for fixture \(fixtureId)")
                        }

                        if !payload.missingCreatureIds.isEmpty {
                            print("Missing creatures (soft warning, fixture still saves):")
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

        // MARK: upsert

        struct Upsert: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create or update a DMX fixture from a JSON file"
            )

            @Argument(help: "Path to the fixture JSON file to upsert")
            var inputPath: String

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                let rawJson = try readJsonFile(at: inputPath)

                let decoder = JSONDecoder()
                let fixture: DmxFixture
                do {
                    fixture = try decoder.decode(DmxFixture.self, from: Data(rawJson.utf8))
                } catch {
                    throw failWithMessage(
                        "Could not parse fixture JSON locally: \(error.localizedDescription)")
                }

                try await tracedRun("fixtures.upsert", config: globalOptions) { server in
                    let result = await server.upsertFixture(fixture)
                    switch result {
                    case .success(let saved):
                        print("✅ Saved fixture \(saved.name) (\(saved.id))")
                    case .failure(let error):
                        throw failWithMessage(
                            "Upsert failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: delete

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a DMX fixture by ID"
            )

            @Argument(help: "Fixture ID (UUID) to delete")
            var fixtureId: DmxFixtureIdentifier

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                try await tracedRun("fixtures.delete", config: globalOptions) { server in
                    let result = await server.deleteFixture(id: fixtureId)
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

        // MARK: universe

        struct Universe: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Assign or clear the persisted E1.31 universe for a fixture"
            )

            @Argument(help: "Fixture ID (UUID)")
            var fixtureId: DmxFixtureIdentifier

            @Option(help: "Universe number to assign (1–63999)")
            var set: UInt32?

            @Flag(help: "Clear the existing universe assignment")
            var clear: Bool = false

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                if (set == nil) == !clear {
                    throw failWithMessage(
                        "Choose exactly one of --set <N> or --clear.")
                }

                try await tracedRun("fixtures.universe", config: globalOptions) { server in
                    if let universe = set {
                        guard (1...63999).contains(universe) else {
                            throw failWithMessage(
                                "Universe must be in [1, 63999] (E1.31 range).")
                        }
                        let result = await server.setFixtureUniverse(
                            id: fixtureId, universe: universe)
                        switch result {
                        case .success(let fixture):
                            let assigned = fixture.assignedUniverse.map(String.init) ?? "—"
                            print(
                                "✅ Fixture '\(fixture.name)' (\(fixture.id)) is now on universe \(assigned)"
                            )
                        case .failure(let error):
                            throw failWithMessage(
                                "Universe assignment failed: \(ServerError.detailedMessage(from: error))"
                            )
                        }
                    } else {
                        let result = await server.clearFixtureUniverse(id: fixtureId)
                        switch result {
                        case .success(let fixture):
                            print(
                                "✅ Fixture '\(fixture.name)' (\(fixture.id)) universe cleared")
                        case .failure(let error):
                            throw failWithMessage(
                                "Universe clear failed: \(ServerError.detailedMessage(from: error))"
                            )
                        }
                    }
                }
            }
        }

        // MARK: live

        struct Live: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Drive raw DMX values on a fixture (slider-style live control)",
                discussion:
                    "POSTs to /fixture/{id}/live. Server holds the values until timeout_ms elapses, then blacks out. Live cancels any active pattern hard and refuses new pattern triggers on this fixture until the deadline elapses."
            )

            @Argument(help: "Fixture ID (UUID)")
            var fixtureId: DmxFixtureIdentifier

            @Option(
                name: .customLong("channel"),
                help:
                    "Channel value in the form 'name=value' (value in 0..255). Repeat for multiple channels."
            )
            var channels: [String] = []

            @Option(name: .customLong("timeout-ms"), help: "Blackout deadline in ms (1–600000)")
            var timeoutMs: UInt32 = 1000

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                guard !channels.isEmpty else {
                    throw failWithMessage(
                        "At least one --channel name=value pair is required.")
                }
                guard (1...600_000).contains(timeoutMs) else {
                    throw failWithMessage("--timeout-ms must be in [1, 600000].")
                }

                var values: [FixturePatternValue] = []
                for entry in channels {
                    let parts = entry.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else {
                        throw failWithMessage(
                            "Invalid --channel '\(entry)', expected 'name=value'.")
                    }
                    let name = String(parts[0])
                    guard let raw = Int(parts[1]), (0...255).contains(raw) else {
                        throw failWithMessage(
                            "Invalid value in --channel '\(entry)', expected integer 0..255.")
                    }
                    values.append(
                        FixturePatternValue(channel: name, value: UInt8(raw)))
                }

                let sendValues = values
                try await tracedRun("fixtures.live", config: globalOptions) { server in
                    let result = await server.setFixtureLive(
                        id: fixtureId, values: sendValues, timeoutMs: timeoutMs)
                    switch result {
                    case .success(let fixture):
                        print(
                            "✅ Live applied to '\(fixture.name)' (\(fixture.id)) — \(sendValues.count) channel(s), \(timeoutMs)ms"
                        )
                    case .failure(let error):
                        throw failWithMessage(
                            "Live update failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }

        // MARK: trigger

        struct Trigger: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Manually fire a pattern on a fixture",
                discussion:
                    "POSTs to /fixture/{id}/pattern/{pid}/trigger. With --stop-after-ms the server schedules an auto-stop; without it the pattern holds until something else stops it. The fixture must already have an assigned universe or the server returns 400."
            )

            @Argument(help: "Fixture ID (UUID)")
            var fixtureId: DmxFixtureIdentifier

            @Argument(help: "Pattern ID (UUID) belonging to that fixture")
            var patternId: FixturePatternIdentifier

            @Option(name: .customLong("stop-after-ms"), help: "Auto-stop after N ms (1–600000)")
            var stopAfterMs: UInt32?

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {
                if let ms = stopAfterMs, !(1...600_000).contains(ms) {
                    throw failWithMessage(
                        "--stop-after-ms must be in (0, 600000] if provided.")
                }

                try await tracedRun("fixtures.trigger", config: globalOptions) { server in
                    let result = await server.triggerFixturePattern(
                        fixtureId: fixtureId,
                        patternId: patternId,
                        stopAfterMs: stopAfterMs
                    )
                    switch result {
                    case .success(let fixture):
                        let suffix = stopAfterMs.map { " (auto-stop in \($0)ms)" } ?? " (hold)"
                        print(
                            "✅ Pattern fired on '\(fixture.name)' (\(fixture.id))\(suffix)")
                    case .failure(let error):
                        throw failWithMessage(
                            "Trigger failed: \(ServerError.detailedMessage(from: error))")
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

private func readJsonFile(at path: String) throws -> String {
    let inputURL = URL(fileURLWithPath: path).standardizedFileURL
    let fileManager = FileManager.default

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
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

func fixtureDetails(_ fixture: DmxFixture) -> String {
    var lines: [String] = []
    lines.append("Fixture: \(fixture.name) (\(fixture.id))")
    lines.append("  Type:           \(fixture.type.rawValue)")
    lines.append("  Channel Offset: \(fixture.channelOffset)")
    if let u = fixture.assignedUniverse {
        lines.append("  Universe:       \(u)")
    } else {
        lines.append("  Universe:       (unassigned — no DMX output)")
    }

    lines.append("")
    lines.append("Channels (\(fixture.channels.count)):")
    for channel in fixture.channels {
        let absolute = Int(fixture.channelOffset) + Int(channel.offset)
        lines.append(
            "  • \(channel.name) [+\(channel.offset) → abs \(absolute), kind=\(channel.kind)]")
    }

    lines.append("")
    lines.append("Patterns (\(fixture.patterns.count)):")
    for pattern in fixture.patterns {
        lines.append("  • \(pattern.name) (\(pattern.id))")
        lines.append(
            "      fade_in=\(pattern.fadeInMs)ms hold=\(pattern.holdMs)ms fade_out=\(pattern.fadeOutMs)ms"
        )
        for value in pattern.values {
            lines.append("      - \(value.channel) = \(value.value)")
        }
    }

    lines.append("")
    lines.append("Bindings (\(fixture.bindings.count)):")
    for binding in fixture.bindings {
        let reason = binding.onReason?.rawValue ?? "any"
        let state = binding.onState?.rawValue ?? "any"
        lines.append(
            "  • creature=\(binding.creatureId) reason=\(reason) state=\(state) → pattern=\(binding.patternId)"
        )
    }

    return lines.joined(separator: "\n")
}
