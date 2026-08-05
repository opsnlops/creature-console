import Foundation
import Testing

@testable import Common

@Suite("Dialog stage binding")
struct DialogStageBindingTests {

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Render request

    @Test("omits stage_id when no stage is bound")
    func omitsStageIdWhenUnbound() throws {
        let request = DialogRequest.fromScript(UUID(), persistence: .adhoc)
        #expect(try object(request)["stage_id"] == nil)
    }

    @Test("sends stage_id lowercased when a stage is bound")
    func sendsLowercasedStageId() throws {
        let stageID = UUID()
        let request = DialogRequest.fromScript(UUID(), persistence: .permanent, stageId: stageID)
        #expect(try object(request)["stage_id"] as? String == stageID.uuidString.lowercased())
    }

    @Test("an inline-turns render can bind a stage too")
    func inlineTurnsCanBindAStage() throws {
        let stageID = UUID()
        let request = DialogRequest.fromTurns(
            [DialogScriptTurn(creatureId: "abc", text: "hello")],
            persistence: .adhoc,
            stageId: stageID)
        let encoded = try object(request)

        #expect(encoded["stage_id"] as? String == stageID.uuidString.lowercased())
        #expect(encoded["turns"] != nil)
        #expect(encoded["script_id"] == nil)
    }

    // MARK: - Script

    @Test("decodes a script's stage_id")
    func decodesScriptStageId() throws {
        let stageID = UUID()
        let json = """
            {"id":"\(UUID().uuidString.lowercased())","title":"Scene 3","turns":[],
             "stage_id":"\(stageID.uuidString.lowercased())"}
            """
        let script = try JSONDecoder().decode(DialogScript.self, from: Data(json.utf8))
        #expect(script.stageId == stageID)
    }

    @Test("treats an empty stage_id as no stage rather than failing the decode")
    func emptyStageIdDecodesAsNil() throws {
        let json = """
            {"id":"\(UUID().uuidString.lowercased())","title":"Scene 3","turns":[],"stage_id":""}
            """
        let script = try JSONDecoder().decode(DialogScript.self, from: Data(json.utf8))
        #expect(script.stageId == nil)
    }

    @Test("a script with no stage_id decodes cleanly")
    func missingStageIdDecodes() throws {
        let json = #"{"id":"\#(UUID().uuidString.lowercased())","title":"Scene 3","turns":[]}"#
        let script = try JSONDecoder().decode(DialogScript.self, from: Data(json.utf8))
        #expect(script.stageId == nil)
    }

    @Test("round-trips a script's stage binding")
    func roundTripsScriptStageBinding() throws {
        let original = DialogScript(
            id: UUID(), title: "Scene 3", notes: "", turns: [], stageId: UUID())
        let decoded = try JSONDecoder().decode(
            DialogScript.self, from: try JSONEncoder().encode(original))
        #expect(decoded.stageId == original.stageId)
        #expect(decoded == original)
    }

    @Test("the upsert body carries the stage binding but not the server-managed fields")
    func upsertCarriesStageBinding() throws {
        let stageID = UUID()
        let script = DialogScript(
            id: UUID(), title: "Scene 3", notes: "n", turns: [], stageId: stageID,
            createdAt: 1, updatedAt: 2)
        let encoded = try object(UpsertDialogScriptRequest(script))

        #expect(encoded["stage_id"] as? String == stageID.uuidString.lowercased())
        #expect(encoded["id"] == nil)
        #expect(encoded["created_at"] == nil)
        #expect(encoded["updated_at"] == nil)
    }

    @Test("an unbound script sends no stage_id, so omission can't clear one")
    func upsertOmitsAbsentStageBinding() throws {
        let script = DialogScript(id: UUID(), title: "Scene 3", notes: "", turns: [])
        #expect(try object(UpsertDialogScriptRequest(script))["stage_id"] == nil)
    }
}
