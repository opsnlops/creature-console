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

    @Test("an unbound script sends an empty stage_id, which the server treats as an explicit clear")
    func upsertSendsEmptyStringForNoStage() throws {
        // Verified against the deployed server: an *absent* key preserves the stored binding
        // (protecting stage-unaware clients), while "" clears it. A stage-aware client's nil is a
        // decision, so the field is always sent.
        let script = DialogScript(id: UUID(), title: "Scene 3", notes: "", turns: [])
        #expect(try object(UpsertDialogScriptRequest(script))["stage_id"] as? String == "")
    }
}

@Suite("Accepted voice take")
struct DialogAcceptedVoiceTests {

    @Test("round-trips on a script and never travels in the upsert")
    func roundTripsAndStaysOutOfUpsert() throws {
        let voice = DialogAcceptedVoice(
            generationId: UUID(),
            dialogCacheKey: String(repeating: "ab", count: 32),
            acceptedAt: 1_786_100_000_000)
        let script = DialogScript(
            id: UUID(), title: "Scene", notes: "", turns: [], acceptedVoice: voice)

        let decoded = try JSONDecoder().decode(
            DialogScript.self, from: try JSONEncoder().encode(script))
        #expect(decoded.acceptedVoice == voice)

        // Like background_music: acceptance is server-managed via the accept endpoint, so an
        // ordinary script edit can't clear it by omission.
        let upsert = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(UpsertDialogScriptRequest(script))) as! [String: Any]
        #expect(upsert["accepted_voice"] == nil)
    }

    @Test("freshness is a cache-key comparison, case-insensitive, and nil-safe")
    func freshnessComparesCacheKeys() {
        let key = String(repeating: "cd", count: 32)
        let voice = DialogAcceptedVoice(generationId: UUID(), dialogCacheKey: key, acceptedAt: 0)

        #expect(voice.isFresh(forCacheKey: key))
        #expect(voice.isFresh(forCacheKey: key.uppercased()))
        #expect(!voice.isFresh(forCacheKey: String(repeating: "ef", count: 32)))
        #expect(!voice.isFresh(forCacheKey: nil))
        #expect(!voice.isFresh(forCacheKey: ""))
    }

    @Test("decodes from the server's wire shape")
    func decodesWireShape() throws {
        let json = """
            {"generation_id":"\(UUID().uuidString.lowercased())",
             "dialog_cache_key":"\(String(repeating: "12", count: 32))",
             "accepted_at": 1786100000000}
            """
        let voice = try JSONDecoder().decode(DialogAcceptedVoice.self, from: Data(json.utf8))
        #expect(voice.acceptedAt == 1_786_100_000_000)
        #expect(voice.acceptedAtDate.timeIntervalSince1970 > 0)
    }

    @Test("a script without an acceptance decodes cleanly")
    func absentAcceptanceDecodes() throws {
        let json = #"{"id":"\#(UUID().uuidString.lowercased())","title":"S","turns":[]}"#
        let script = try JSONDecoder().decode(DialogScript.self, from: Data(json.utf8))
        #expect(script.acceptedVoice == nil)
    }
}
