import Foundation
import Testing

@testable import Common

@Suite("DialogRequest encoding")
struct DialogRequestDTOTests {

    private func encodeToObject(_ request: DialogRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test("inline turns request omits script_id")
    func turnsOnly() throws {
        let request = DialogRequest.fromTurns(
            [DialogScriptTurn(creatureId: "abc", text: "hi")], persistence: .adhoc)
        let obj = try encodeToObject(request)
        #expect(obj["script_id"] == nil)
        #expect(obj["turns"] != nil)
        #expect(obj["persistence"] as? String == "adhoc")
    }

    @Test("script request omits turns")
    func scriptOnly() throws {
        let id = UUID()
        let request = DialogRequest.fromScript(id, persistence: .permanent)
        let obj = try encodeToObject(request)
        #expect(obj["turns"] == nil)
        #expect(obj["script_id"] as? String == id.uuidString.lowercased())
        #expect(obj["persistence"] as? String == "permanent")
    }

    @Test("persistence is always present")
    func persistenceAlwaysPresent() throws {
        let obj = try encodeToObject(
            DialogRequest.fromTurns([], persistence: .permanent))
        #expect(obj["persistence"] as? String == "permanent")
    }

    @Test("generation_id is emitted lowercased")
    func generationLowercased() throws {
        let gen = UUID()
        let request = DialogRequest.fromScript(
            UUID(), persistence: .adhoc, generationId: gen)
        let obj = try encodeToObject(request)
        #expect(obj["generation_id"] as? String == gen.uuidString.lowercased())
    }

    @Test("optional fields are omitted when nil")
    func optionalsOmitted() throws {
        let obj = try encodeToObject(
            DialogRequest.fromTurns([], persistence: .adhoc))
        #expect(obj["autoplay"] == nil)
        #expect(obj["title"] == nil)
        #expect(obj["generation_id"] == nil)
    }

    @Test("autoplay and title round-trip into the body")
    func autoplayAndTitle() throws {
        let obj = try encodeToObject(
            DialogRequest.fromTurns(
                [], persistence: .permanent, autoplay: true, title: "Scene 1"))
        #expect(obj["autoplay"] as? Bool == true)
        #expect(obj["title"] as? String == "Scene 1")
    }
}
