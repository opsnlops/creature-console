import Foundation
import Testing

@testable import Common

@Suite("DialogScript model")
struct DialogScriptTests {

    @Test("decodes a server script with snake_case keys and epoch-ms timestamps")
    func decodesServerScript() throws {
        let json = """
            {
              "id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
              "title": "Beaky and Mango — UFO sighting",
              "notes": "First draft",
              "turns": [
                { "creature_id": "e93b9a7a-1704-11ef-84b9-3b37dddeb225", "text": "[excited] Beaky!" },
                { "creature_id": "4754fc0e-1706-11ef-931d-bbb95a696e2e", "text": "[skeptical] What now?" }
              ],
              "created_at": 1748579999000,
              "updated_at": 1748580015000
            }
            """
        let script = try JSONDecoder().decode(DialogScript.self, from: Data(json.utf8))
        #expect(script.id == UUID(uuidString: "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2"))
        #expect(script.title == "Beaky and Mango — UFO sighting")
        #expect(script.notes == "First draft")
        #expect(script.turns.count == 2)
        #expect(script.turns[0].creatureId == "e93b9a7a-1704-11ef-84b9-3b37dddeb225")
        #expect(script.turns[1].text == "[skeptical] What now?")
        #expect(script.createdAt == 1_748_579_999_000)
        #expect(script.updatedAt == 1_748_580_015_000)
    }

    @Test("derives Date accessors from epoch-ms timestamps")
    func derivesDates() {
        let script = DialogScript(
            id: UUID(), title: "t", notes: "", turns: [], createdAt: 1_748_579_999_000,
            updatedAt: nil)
        #expect(
            script.createdAtDate == Date(timeIntervalSince1970: 1_748_579_999.0))
        #expect(script.updatedAtDate == nil)
    }

    @Test("decodes when optional fields are absent")
    func decodesWithMissingOptionals() throws {
        let json = """
            { "id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2", "title": "Minimal" }
            """
        let script = try JSONDecoder().decode(DialogScript.self, from: Data(json.utf8))
        #expect(script.notes == "")
        #expect(script.turns.isEmpty)
        #expect(script.createdAt == nil)
        #expect(script.updatedAt == nil)
    }

    @Test("encodes the id as a lowercase UUID string")
    func encodesLowercaseId() throws {
        let id = UUID()  // uuidString is uppercase
        let script = DialogScript(id: id, title: "T", notes: "", turns: [])
        let data = try JSONEncoder().encode(script)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["id"] as? String == id.uuidString.lowercased())
    }

    @Test("turn id is client-only and never encoded")
    func turnIdNotEncoded() throws {
        let turn = DialogScriptTurn(creatureId: "abc", text: "hi")
        let data = try JSONEncoder().encode(turn)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(Set(obj.keys) == ["creature_id", "text"])
        #expect(obj["id"] == nil)
    }

    @Test("each decoded turn gets a fresh client id")
    func turnsGetFreshIds() throws {
        let json = """
            [ { "creature_id": "a", "text": "x" }, { "creature_id": "a", "text": "x" } ]
            """
        let turns = try JSONDecoder().decode([DialogScriptTurn].self, from: Data(json.utf8))
        #expect(turns.count == 2)
        #expect(turns[0].id != turns[1].id)
    }

    @Test("round-trips through encode/decode")
    func roundTrips() throws {
        let original = DialogScript.mock()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DialogScript.self, from: Data(data))
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.notes == original.notes)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.turns.map(\.creatureId) == original.turns.map(\.creatureId))
        #expect(decoded.turns.map(\.text) == original.turns.map(\.text))
    }

    @Test("newEmpty produces a usable blank script")
    func newEmptyIsBlank() {
        let script = DialogScript.newEmpty()
        #expect(script.title.isEmpty)
        #expect(script.notes.isEmpty)
        #expect(script.turns.isEmpty)
        #expect(script.createdAt == nil)
    }

    @Test("upsert request body carries only the editable fields")
    func upsertBodyOmitsServerManagedFields() throws {
        let script = DialogScript.mock()  // has id + created_at + updated_at
        let data = try JSONEncoder().encode(UpsertDialogScriptRequest(script))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // The server's upsert DTO rejects unknown fields, so we must send exactly these three.
        #expect(Set(obj.keys) == ["title", "notes", "turns"])
        #expect(obj["id"] == nil)
        #expect(obj["created_at"] == nil)
        #expect(obj["updated_at"] == nil)
        #expect((obj["turns"] as? [[String: Any]])?.count == script.turns.count)
    }
}
