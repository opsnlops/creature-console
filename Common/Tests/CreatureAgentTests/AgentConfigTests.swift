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
        #expect(config.localLlmMaxTokens == 200)
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
