import Foundation
import Testing

@testable import Common

@Suite("Stage model tests")
struct StageTests {

    private func encoder() -> JSONEncoder {
        JSONEncoder()
    }

    private func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    // MARK: - Initialization

    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        let id = UUID()
        let stage = Stage(
            id: id, title: "Mainstage", notes: "notes", version: 1,
            placements: [StagePlacement(creatureID: "abc", x: 1, y: 2, z: 3, yaw: 45)],
            audio: StageAudioSettings(), createdAt: 100, updatedAt: 200)

        #expect(stage.id == id)
        #expect(stage.title == "Mainstage")
        #expect(stage.notes == "notes")
        #expect(stage.version == 1)
        #expect(stage.placements.count == 1)
        #expect(stage.createdAt == 100)
        #expect(stage.updatedAt == 200)
    }

    @Test("newEmpty defaults to the current coordinate frame")
    func newEmptyUsesCurrentVersion() {
        let stage = Stage.newEmpty(title: "Travel")
        #expect(stage.version == StageLimits.currentVersion)
        #expect(stage.placements.isEmpty)
        #expect(stage.title == "Travel")
    }

    // MARK: - Yaw normalization

    @Test("normalizes yaw into (-180, 180]")
    func normalizesYaw() {
        #expect(StagePlacement.normalizedYaw(0) == 0)
        #expect(StagePlacement.normalizedYaw(90) == 90)
        #expect(StagePlacement.normalizedYaw(180) == 180)
        #expect(StagePlacement.normalizedYaw(370) == 10)
        #expect(StagePlacement.normalizedYaw(-90) == -90)
        #expect(StagePlacement.normalizedYaw(720) == 0)
        #expect(StagePlacement.normalizedYaw(-370) == -10)
    }

    @Test("folds -180 onto +180 so one heading has one representation")
    func foldsNegativeHalfTurn() {
        #expect(StagePlacement.normalizedYaw(-180) == 180)
        #expect(StagePlacement.normalizedYaw(540) == 180)
    }

    @Test("treats a non-finite yaw as facing forward rather than propagating NaN")
    func handlesNonFiniteYaw() {
        #expect(StagePlacement.normalizedYaw(.nan) == 0)
        #expect(StagePlacement.normalizedYaw(.infinity) == 0)
    }

    @Test("normalizes yaw on construction and on decode")
    func normalizesYawOnConstructionAndDecode() throws {
        let placement = StagePlacement(creatureID: "abc", x: 0, z: 0, yaw: 370)
        #expect(placement.yaw == 10)

        let json = #"{"creature_id":"abc","x":0,"y":0,"z":0,"yaw":-190}"#
        let decoded = try decoder().decode(StagePlacement.self, from: Data(json.utf8))
        #expect(decoded.yaw == 170)
    }

    // MARK: - Encoding / decoding

    @Test("encodes placements with the server's snake_case keys")
    func encodesSnakeCaseKeys() throws {
        let placement = StagePlacement(
            creatureID: "abc", creatureName: "Beaky", audioChannel: 1, x: -1.5, y: 0.25, z: -3,
            yaw: 35, gain: 0.8, isMuted: true)
        let data = try encoder().encode(placement)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["creature_id"] as? String == "abc")
        #expect(object["creature_name"] as? String == "Beaky")
        #expect(object["audio_channel"] as? Int == 1)
        #expect(object["muted"] as? Bool == true)
        #expect(object["yaw"] != nil)
    }

    @Test("encodes the audio block with the server's snake_case keys")
    func encodesAudioSnakeCaseKeys() throws {
        let data = try encoder().encode(StageAudioSettings())
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["monitoring_delay_ms"] as? Int == 10)
        #expect(object["common_playout_delay_ms"] as? Int == 20)
        #expect(object["background_music_gain"] != nil)
        #expect(object["reverb_blend"] != nil)
    }

    @Test("encodes the stage id as a lowercase uuid string")
    func encodesLowercaseIdentifier() throws {
        let id = UUID()
        let data = try encoder().encode(Stage(id: id, title: "S"))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["id"] as? String == id.uuidString.lowercased())
    }

    @Test("round-trips a full stage")
    func roundTripsFullStage() throws {
        let original = Stage.mock()
        let decoded = try decoder().decode(Stage.self, from: try encoder().encode(original))
        #expect(decoded == original)
    }

    @Test("decodes a server document")
    func decodesServerDocument() throws {
        let json = """
            {
              "id": "0f1a4d3e-0000-4000-8000-000000000001",
              "title": "Mainstage",
              "notes": "",
              "version": 1,
              "placements": [
                { "creature_id": "abc", "x": -2.4, "y": 0.1, "z": -3.0, "yaw": 35.0,
                  "audio_channel": 1, "gain": 1.0, "muted": false }
              ],
              "audio": { "monitoring_delay_ms": 10, "common_playout_delay_ms": 20,
                         "background_music_gain": 0.7, "reverb_blend": 0.08 },
              "created_at": 1754240000000,
              "updated_at": 1754250000000
            }
            """
        let stage = try decoder().decode(Stage.self, from: Data(json.utf8))

        #expect(stage.title == "Mainstage")
        #expect(stage.placements.count == 1)
        #expect(stage.placements[0].creatureID == "abc")
        #expect(stage.placements[0].audioChannel == 1)
        #expect(stage.audio.monitoringDelayMilliseconds == 10)
        #expect(stage.updatedAt == 1_754_250_000_000)
        #expect(stage.updatedAtDate != nil)
    }

    @Test("defaults notes, placements, and audio when the server omits them")
    func defaultsMissingFields() throws {
        let json = #"{"id":"0f1a4d3e-0000-4000-8000-000000000001","title":"Bare"}"#
        let stage = try decoder().decode(Stage.self, from: Data(json.utf8))

        #expect(stage.notes.isEmpty)
        #expect(stage.placements.isEmpty)
        #expect(stage.version == StageLimits.currentVersion)
        #expect(stage.audio == StageAudioSettings())
    }

    @Test("fails when the stage id is missing")
    func failsOnMissingIdentifier() {
        let json = #"{"title":"No id"}"#
        #expect(throws: DecodingError.self) {
            try decoder().decode(Stage.self, from: Data(json.utf8))
        }
    }

    // MARK: - Forward compatibility

    @Test("preserves unknown placement keys across a round-trip")
    func preservesUnknownPlacementKeys() throws {
        let json = """
            {"creature_id":"abc","x":0,"y":0,"z":0,"yaw":0,"tint_hex":"#34C759","perch_number":3}
            """
        let placement = try decoder().decode(StagePlacement.self, from: Data(json.utf8))
        #expect(placement.additionalFields["tint_hex"] == .string("#34C759"))
        #expect(placement.additionalFields["perch_number"] == .number(3))

        let object = try #require(
            try JSONSerialization.jsonObject(with: try encoder().encode(placement))
                as? [String: Any])
        #expect(object["tint_hex"] as? String == "#34C759")
        #expect(object["perch_number"] as? Double == 3)
        #expect(object["creature_id"] as? String == "abc")
    }

    @Test("preserves unknown audio keys across a round-trip")
    func preservesUnknownAudioKeys() throws {
        let json = #"{"monitoring_delay_ms":12,"future_setting":true}"#
        let audio = try decoder().decode(StageAudioSettings.self, from: Data(json.utf8))
        #expect(audio.monitoringDelayMilliseconds == 12)
        #expect(audio.additionalFields["future_setting"] == .bool(true))

        let object = try #require(
            try JSONSerialization.jsonObject(with: try encoder().encode(audio)) as? [String: Any])
        #expect(object["future_setting"] as? Bool == true)
        #expect(object["monitoring_delay_ms"] as? Int == 12)
    }

    @Test("does not capture known keys as unknown extras")
    func doesNotDuplicateKnownKeys() throws {
        let json = #"{"creature_id":"abc","x":1,"y":2,"z":3,"yaw":4,"gain":0.5,"muted":true}"#
        let placement = try decoder().decode(StagePlacement.self, from: Data(json.utf8))
        #expect(placement.additionalFields.isEmpty)
    }

    // MARK: - Upsert request

    @Test("upsert request omits the server-managed fields")
    func upsertRequestOmitsServerManagedFields() throws {
        let data = try encoder().encode(UpsertStageRequest(Stage.mock()))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["id"] == nil)
        #expect(object["created_at"] == nil)
        #expect(object["updated_at"] == nil)
        #expect(object["title"] as? String == "Mainstage")
        #expect(object["placements"] != nil)
        #expect(object["audio"] != nil)
        #expect(object["version"] as? Int == 1)
    }

    // MARK: - Validation

    @Test("accepts a well-formed stage")
    func acceptsValidStage() {
        #expect(Stage.mock().validationProblem == nil)
        #expect(Stage.mock().isValid)
    }

    @Test("rejects a coordinate outside the stage box")
    func rejectsOutOfRangeCoordinate() {
        var stage = Stage.mock()
        stage.placements[0].x = 6
        #expect(stage.validationProblem != nil)
    }

    @Test("accepts a coordinate exactly on the boundary")
    func acceptsBoundaryCoordinate() {
        var stage = Stage.mock()
        stage.placements[0].x = StageLimits.coordinateLimit
        stage.placements[0].z = -StageLimits.coordinateLimit
        #expect(stage.validationProblem == nil)
    }

    @Test("rejects a non-finite coordinate")
    func rejectsNonFiniteCoordinate() {
        var stage = Stage.mock()
        stage.placements[0].y = .nan
        #expect(stage.validationProblem != nil)
    }

    @Test("rejects two placements for the same creature")
    func rejectsDuplicateCreature() {
        var stage = Stage.mock()
        stage.placements.append(stage.placements[0])
        let problem = try? #require(stage.validationProblem)
        #expect(problem?.contains("more than once") == true)
    }

    @Test("rejects more placements than there are audio lanes")
    func rejectsTooManyPlacements() {
        var stage = Stage.newEmpty(title: "Crowded")
        stage.placements = (0...StageLimits.maxPlacements).map {
            StagePlacement(creatureID: "creature-\($0)", x: 0, z: 0)
        }
        #expect(stage.placements.count > StageLimits.maxPlacements)
        #expect(stage.validationProblem != nil)
    }

    @Test("accepts exactly the maximum number of placements")
    func acceptsMaximumPlacements() {
        var stage = Stage.newEmpty(title: "Full")
        stage.placements = (0..<StageLimits.maxPlacements).map {
            StagePlacement(creatureID: "creature-\($0)", x: 0, z: 0)
        }
        #expect(stage.validationProblem == nil)
    }

    @Test("rejects an over-long title")
    func rejectsLongTitle() {
        var stage = Stage.mock()
        stage.title = String(repeating: "a", count: StageLimits.maxTitle + 1)
        #expect(stage.validationProblem != nil)
    }

    @Test("rejects a coordinate frame this client doesn't understand")
    func rejectsUnknownVersion() {
        var stage = Stage.mock()
        stage.version = StageLimits.currentVersion + 1
        #expect(stage.validationProblem != nil)
    }

    @Test("rejects a placement with an empty creature id")
    func rejectsEmptyCreatureIdentifier() {
        var stage = Stage.mock()
        stage.placements[0].creatureID = ""
        #expect(stage.validationProblem != nil)
    }

    // MARK: - Lookup

    @Test("finds a placement by creature id")
    func findsPlacementByCreature() {
        let stage = Stage.mock()
        let creatureID = stage.placements[1].creatureID
        #expect(stage.placement(for: creatureID)?.creatureID == creatureID)
        #expect(stage.placement(for: "nobody") == nil)
    }

    // MARK: - Equality & hashing

    @Test("equal stages hash the same")
    func equalStagesHashEqually() {
        let stage = Stage.mock()
        var copy = stage
        #expect(stage == copy)
        #expect(stage.hashValue == copy.hashValue)

        copy.placements[0].yaw = 90
        #expect(stage != copy)
    }
}

@Suite("Stage list and animation DTO tests")
struct StageDTOTests {

    @Test("decodes the stage list envelope")
    func decodesStageList() throws {
        let json = """
            {"count":1,"items":[{"id":"0f1a4d3e-0000-4000-8000-000000000001","title":"Mainstage"}]}
            """
        let dto = try JSONDecoder().decode(StageListDTO.self, from: Data(json.utf8))
        #expect(dto.count == 1)
        #expect(dto.items.first?.title == "Mainstage")
    }

    @Test("decodes the staleness envelope")
    func decodesStalenessEnvelope() throws {
        let json = """
            { "count": 2, "stale_count": 1, "stage_updated_at": 1754250000000,
              "items": [
                { "animation_id": "a1", "title": "Scene 3", "source_script_id": "s1",
                  "source_stage_updated_at": 1754240000000, "stale": true },
                { "animation_id": "a2", "title": "Scene 4", "source_script_id": "s2",
                  "source_stage_updated_at": 1754250000000, "stale": false }
              ] }
            """
        let dto = try JSONDecoder().decode(StageAnimationsDTO.self, from: Data(json.utf8))

        #expect(dto.count == 2)
        #expect(dto.staleCount == 1)
        #expect(dto.stageUpdatedAt == 1_754_250_000_000)
        #expect(dto.items.first?.isStale == true)
        #expect(dto.items.first?.animationID == "a1")
        #expect(dto.stalenessSummary == "1 of 2 animations out of date")
    }

    @Test("reports no staleness summary when everything is current")
    func noStalenessSummaryWhenCurrent() throws {
        let json = #"{"count":2,"stale_count":0,"stage_updated_at":0,"items":[]}"#
        let dto = try JSONDecoder().decode(StageAnimationsDTO.self, from: Data(json.utf8))
        #expect(dto.stalenessSummary == nil)
    }
}
