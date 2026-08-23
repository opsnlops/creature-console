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
        // The server's upsert DTO rejects unknown fields, so we must send exactly these four.
        // stage_id is always present ("" = unbound) — the server preserves the stored binding
        // when the key is absent, and this client's nil is a decision, not ignorance.
        #expect(Set(obj.keys) == ["title", "notes", "turns", "stage_id"])
        #expect(obj["id"] == nil)
        #expect(obj["created_at"] == nil)
        #expect(obj["updated_at"] == nil)
        #expect((obj["turns"] as? [[String: Any]])?.count == script.turns.count)
    }
}


@Suite("DialogScriptTurn identity vs. content")
struct DialogScriptTurnEqualityTests {

    private let creatureId = "5d7c1a02-9b34-4e18-8f6a-2c0d3e5b7a91"

    /// A turn's `id` is a client-only SwiftUI identity, minted fresh on every decode and
    /// deliberately kept off the wire. It must not count toward equality.
    ///
    /// It used to. That made a script decoded from the server unequal to the identical script
    /// held in memory, so `DialogScriptEditor.isDirty` (`script != original`) stayed true
    /// forever after a save — and `isDirty` gates the render id, the Render button, take
    /// acceptance, and music promotion. The editor sat there claiming unsaved changes it
    /// didn't have.
    @Test("two turns with the same creature and text are equal despite different ids")
    func sameContentDifferentIdsAreEqual() {
        let a = DialogScriptTurn(creatureId: creatureId, text: "Did you hear that?")
        let b = DialogScriptTurn(creatureId: creatureId, text: "Did you hear that?")

        #expect(a.id != b.id)
        #expect(a == b)

        var hasherA = Hasher()
        a.hash(into: &hasherA)
        var hasherB = Hasher()
        b.hash(into: &hasherB)
        #expect(hasherA.finalize() == hasherB.finalize())
    }

    @Test("content still decides inequality")
    func contentDecidesInequality() {
        let base = DialogScriptTurn(creatureId: creatureId, text: "Hello")
        #expect(base != DialogScriptTurn(creatureId: creatureId, text: "Hello!"))
        #expect(
            base
                != DialogScriptTurn(
                    creatureId: "6e8d2b13-ac45-4f29-9a7b-3d1e4f6c8b02", text: "Hello"))
    }

    /// The editor's dirty check in miniature: save, take the server's canonical copy back, and
    /// the unchanged script must compare equal to it.
    @Test("a script survives a save round trip as equal")
    func scriptRoundTripsAsEqual() throws {
        let script = DialogScript(
            id: UUID(),
            title: "Morning Chatter",
            notes: "",
            turns: [
                DialogScriptTurn(creatureId: creatureId, text: "Good morning!"),
                DialogScriptTurn(creatureId: creatureId, text: "Good morning!"),
            ])

        let data = try JSONEncoder().encode(script)
        let canonical = try JSONDecoder().decode(DialogScript.self, from: data)

        #expect(canonical == script, "an unedited script must not read as dirty after a save")
    }
}
