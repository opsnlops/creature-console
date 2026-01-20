import Foundation
import Testing

@testable import creature_agent

@Suite("CreatureAgent AgentConfig")
struct AgentConfigTests {
    @Test("Parses area cooldowns and topics")
    func parsesAreaCooldownsAndTopics() throws {
        let yaml = """
            creatureId: 00000000-0000-0000-0000-000000000000
            openAiApiKey: test
            openAiSystemPrompt: system
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
}

private func writeTemporaryFile(contents: String) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("yaml")
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}
