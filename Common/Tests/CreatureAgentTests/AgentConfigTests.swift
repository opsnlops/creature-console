import Foundation
import Testing

@testable import creature_agent

@Suite("CreatureAgent AgentConfig")
struct AgentConfigTests {
    @Test("Parses area cooldowns and topics")
    func parsesAreaCooldownsAndTopics() throws {
        let yaml = """
            creatureId: 00000000-0000-0000-0000-000000000000
            llmApiKey: test
            llmSystemPrompt: system
            areas:
              - area: Driveway
                cooldownTime: 300s
                items:
                  - topic: home/alerts/driveway/person
                    agentPrompt: driveway person detected
            """

        let config = try AgentConfig.load(from: writeTemporaryFile(contents: yaml))
        #expect(config.areas.count == 1)
        #expect(config.areas[0].area == "Driveway")
        #expect(config.areas[0].cooldownTimeSeconds == 300)
        #expect(config.areas[0].items.count == 1)
        #expect(config.areas[0].items[0].topic == "home/alerts/driveway/person")
    }

    @Test("Defaults to openai backend")
    func defaultsToOpenaiBackend() throws {
        let yaml = """
            creatureId: 00000000-0000-0000-0000-000000000000
            llmApiKey: test-key
            llmSystemPrompt: system
            areas: []
            """

        let config = try AgentConfig.load(from: writeTemporaryFile(contents: yaml))
        #expect(config.llmBackend == .openai)
    }

    @Test("Parses local backend")
    func parsesLocalBackend() throws {
        let yaml = """
            creatureId: 00000000-0000-0000-0000-000000000000
            llmBackend: local
            llmSystemPrompt: system
            llmModel: google/gemma-3-27b
            localLlmHost: 192.168.1.100
            localLlmPort: 5555
            localLlmMaxTokens: 300
            conversationHistorySize: 20
            areas: []
            """

        let config = try AgentConfig.load(from: writeTemporaryFile(contents: yaml))
        #expect(config.llmBackend == .local)
        #expect(config.llmApiKey == nil)
        #expect(config.llmModel == "google/gemma-3-27b")
        #expect(config.localLlmHost == "192.168.1.100")
        #expect(config.localLlmPort == 5555)
        #expect(config.localLlmMaxTokens == 300)
        #expect(config.conversationHistorySize == 20)
    }

    @Test("A world-mode mind lives in the house's time zone, not the host's")
    func parsesWorldTimeZone() throws {
        func load(_ extra: String) throws -> AgentConfig {
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        mode: world
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmBackend: local
                        llmSystemPrompt: system
                        llmModel: mistral-nemo
                        worldUrl: http://127.0.0.1:8001/world/v1
                        areas: []
                        \(extra)
                        """))
        }

        #expect(
            try load("timeZone: America/Los_Angeles").world.timeZone.identifier
                == "America/Los_Angeles")
        #expect(try load("").world.timeZone == TimeZone.current)
        #expect(throws: DecodingError.self) { try load("timeZone: Whidbey/Island") }
    }

    @Test("agentMemoryMcpUrl is optional and must be an http(s) URL (#294)")
    func parsesAgentMemoryURL() throws {
        func load(_ extra: String) throws -> AgentConfig {
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        mode: world
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmBackend: openai
                        llmSystemPrompt: system
                        llmModel: gpt-6-luna
                        worldUrl: http://127.0.0.1:8001/world/v1
                        areas: []
                        \(extra)
                        """))
        }

        #expect(try load("").world.agentMemoryMCPURL == nil)
        #expect(
            try load("agentMemoryMcpUrl: http://10.0.0.5:8787/mcp").world.agentMemoryMCPURL
                == URL(string: "http://10.0.0.5:8787/mcp"))
        // Independent of the world's: a mind may have one, the other, or both.
        #expect(try load("agentMemoryMcpUrl: http://10.0.0.5:8787/mcp").world.worldMCPURL == nil)
        #expect(throws: DecodingError.self) { try load("agentMemoryMcpUrl: notes.local") }
    }

    @Test("The shared settings sit under a bird's own: its keys win, ~ turns one off (#294)")
    func layersOverSharedSettings() throws {
        let base = try writeTemporaryFile(
            contents: """
                # the fleet's production values
                agentMemoryMcpUrl: http://10.0.0.5:8787/mcp
                llmModel: gpt-6-luna
                """)
        func load(_ own: String) throws -> AgentConfig {
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        mode: world
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmBackend: openai
                        llmSystemPrompt: system
                        worldUrl: http://127.0.0.1:8001/world/v1
                        \(own)
                        """), base: base)
        }

        // Inherited when the bird says nothing.
        let plain = try load("")
        #expect(plain.world.agentMemoryMCPURL == URL(string: "http://10.0.0.5:8787/mcp"))
        #expect(plain.llmModel == "gpt-6-luna")
        // The bird's own value wins.
        #expect(try load("llmModel: gpt-6.1-sol").llmModel == "gpt-6.1-sol")
        // ~ turns the shared setting off for this bird.
        #expect(try load("agentMemoryMcpUrl: ~").world.agentMemoryMCPURL == nil)
        // An empty shared file is no settings, not an error.
        let empty = try writeTemporaryFile(contents: "# nothing shared yet\n")
        #expect(
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        mode: world
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmSystemPrompt: system
                        llmModel: mistral-nemo
                        """), base: empty
            ).world.agentMemoryMCPURL == nil)
        // The packaged file itself decodes as shared settings.
        let packaged = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("debian/creature-agent-common.yaml")
        let shipped = try AgentConfig.load(
            from: writeTemporaryFile(
                contents: """
                    mode: world
                    creatureId: 00000000-0000-0000-0000-000000000000
                    llmBackend: openai
                    llmSystemPrompt: system
                    llmModel: gpt-6-luna
                    """), base: packaged)
        #expect(shipped.world.agentMemoryMCPURL?.port == 8787)
    }

    @Test("The flock's packaged configs decode to the production minds, with no prompt (#294)")
    func packagedFlockConfigs() throws {
        let debian = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("debian")
        let common = debian.appendingPathComponent("creature-agent-common.yaml")
        let expected:
            [(bird: String, model: String, tier: String, memory: String, librarian: Bool)] =
                [
                    ("beaky", "gpt-6.1-sol", "fast", "gpt-6-astra", true),
                    ("mango", "gpt-6-luna", "default", "gpt-6.1-sol", false),
                    ("kenny", "gpt-6-luna", "default", "gpt-6.1-sol", false),
                    ("caroll", "gpt-6-luna", "default", "gpt-6.1-sol", false),
                ]
        var creatures: Set<String> = []
        for bird in expected {
            let config = try AgentConfig.load(
                from: debian.appendingPathComponent("creature-agent-\(bird.bird).yaml"),
                base: common)
            #expect(config.mode == .world)
            #expect(config.llmBackend == .openai)
            #expect(config.llmModel == bird.model)
            #expect(config.llmServiceTier == bird.tier)
            #expect(config.llmReasoningEffort == "low")
            #expect(config.llmMemoryModel == bird.memory)
            #expect(config.librarian == bird.librarian)
            #expect(config.llmSystemPrompt.isEmpty)
            #expect(config.world.characterEntityID == "character:\(bird.bird)")
            #expect(config.world.personaPath == "/etc/creature/agent/personas/\(bird.bird).yaml")
            #expect(config.world.worldMCPURL?.absoluteString == "http://127.0.0.1:8001/world/mcp")
            #expect(config.world.agentMemoryMCPURL?.port == 8787)
            #expect(config.world.timeZone.identifier == "America/Los_Angeles")
            creatures.insert("\(config.creatureId)")
        }
        // Four bodies, not one copied four times.
        #expect(creatures.count == 4)
    }

    @Test("Without a persona file, a mind still needs its prompt")
    func promptRequiredWithoutPersona() throws {
        #expect(throws: DecodingError.self) {
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        mode: world
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmModel: gpt-6-luna
                        """))
        }
    }

    @Test("A reasoning effort is low, medium, or high")
    func parsesReasoningEffort() throws {
        func load(_ extra: String) throws -> AgentConfig {
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmSystemPrompt: system
                        llmModel: gpt-6
                        areas: []
                        \(extra)
                        """))
        }
        #expect(try load("llmReasoningEffort: low").llmReasoningEffort == "low")
        #expect(try load("").llmReasoningEffort == nil)
        #expect(throws: DecodingError.self) { try load("llmReasoningEffort: max") }
    }

    @Test("The Decisions model is gpt-6-luna unless told otherwise; the old shadow key is ignored")
    func parsesDecisionsModel() throws {
        func load(_ extra: String) throws -> AgentConfig {
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmSystemPrompt: system
                        llmModel: gpt-6-luna
                        areas: []
                        \(extra)
                        """))
        }
        #expect(try load("").llmDecisionsModel == "gpt-6-luna")
        // A bird's config from the shadow's days (#221) still loads.
        #expect(try load("llmDecisionsShadow: true").llmDecisionsModel == "gpt-6-luna")
    }

    @Test("The birds' words go to Honeycomb unless told otherwise; nonsense is refused (#230)")
    func parsesContentCapture() throws {
        func load(_ extra: String) throws -> AgentConfig {
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmSystemPrompt: system
                        areas: []
                        \(extra)
                        """))
        }
        #expect(try load("").llmCaptureContent == .output)
        #expect(try load("llmCaptureContent: off").llmCaptureContent == .off)
        #expect(try load("llmCaptureContent: all").llmCaptureContent == .all)
        #expect(throws: (any Error).self) { try load("llmCaptureContent: everything") }
        // The librarian is one bird's job, asked for by name (#229).
        #expect(try load("").librarian == false)
        #expect(try load("librarian: true").librarian == true)
    }

    @Test("The nightly memory goes through the Batch API unless told not to, with a bounded wait")
    func parsesMemoryBatch() throws {
        func load(_ extra: String) throws -> AgentConfig {
            try AgentConfig.load(
                from: writeTemporaryFile(
                    contents: """
                        creatureId: 00000000-0000-0000-0000-000000000000
                        llmSystemPrompt: system
                        llmModel: gpt-6
                        areas: []
                        \(extra)
                        """))
        }
        #expect(try load("").llmMemoryBatch == true)
        #expect(try load("").llmMemoryBatchWaitHours == 20)
        #expect(try load("llmMemoryBatch: false").llmMemoryBatch == false)
        #expect(try load("llmMemoryBatchWaitHours: 6").llmMemoryBatchWaitHours == 6)
        #expect(throws: DecodingError.self) { try load("llmMemoryBatchWaitHours: 48") }
        // The day's episodes wait an hour on the batch, and never longer than a batch may (#264).
        #expect(try load("").llmMemoryEpisodesWaitMinutes == 60)
        #expect(try load("llmMemoryEpisodesWaitMinutes: 30").llmMemoryEpisodesWaitMinutes == 30)
        #expect(throws: DecodingError.self) { try load("llmMemoryEpisodesWaitMinutes: 0") }
        #expect(throws: DecodingError.self) {
            try load("llmMemoryBatchWaitHours: 1\nllmMemoryEpisodesWaitMinutes: 90")
        }
    }

    @Test("Uses default values for optional local LLM fields")
    func usesDefaultsForOptionalFields() throws {
        let yaml = """
            creatureId: 00000000-0000-0000-0000-000000000000
            llmSystemPrompt: system
            areas: []
            """

        let config = try AgentConfig.load(from: writeTemporaryFile(contents: yaml))
        #expect(config.llmBackend == .openai)
        #expect(config.llmApiKey == nil)
        #expect(config.llmModel == "gpt-5.2")
        #expect(config.llmTemperature == 1.0)
        #expect(config.localLlmHost == "10.69.66.4")
        #expect(config.localLlmPort == 1234)
        #expect(config.localLlmMaxTokens == 100)
        #expect(config.conversationHistorySize == 10)
    }

    @Test("Parses renamed LLM fields")
    func parsesRenamedLlmFields() throws {
        let yaml = """
            creatureId: 00000000-0000-0000-0000-000000000000
            llmApiKey: sk-test-key
            llmModel: gpt-5.2
            llmSystemPrompt: You are a parrot.
            llmTemperature: 0.8
            areas: []
            """

        let config = try AgentConfig.load(from: writeTemporaryFile(contents: yaml))
        #expect(config.llmApiKey == "sk-test-key")
        #expect(config.llmModel == "gpt-5.2")
        #expect(config.llmSystemPrompt == "You are a parrot.")
        #expect(config.llmTemperature == 0.8)
    }
}

private func writeTemporaryFile(contents: String) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("yaml")
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}
