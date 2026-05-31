import Foundation
import Testing

@testable import Common

@Suite("Storyboard model")
struct StoryboardTests {

    private func encodeToObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    // MARK: - Storyboard document

    @Test("decodes a server storyboard with snake_case keys and epoch-ms timestamps")
    func decodesServerStoryboard() throws {
        let json = """
            {
              "id": "B4F1C0DE-1111-2222-3333-444455556666",
              "title": "Front Porch",
              "notes": "Greet + heckle",
              "tiles": [
                { "id": "11111111-1111-1111-1111-111111111111", "x": 0.06, "y": 0.08,
                  "width": 0.26, "height": 0.2, "label": "Greet", "sf_symbol": "hand.wave.fill",
                  "tint_color_hex": "#34C759",
                  "action": { "type": "ad_hoc_speech", "creature_id": "abc", "resume_playlist": true } }
              ],
              "created_at": 1748579999000,
              "updated_at": 1748580015000
            }
            """
        let board = try JSONDecoder().decode(Storyboard.self, from: Data(json.utf8))
        #expect(board.id == UUID(uuidString: "B4F1C0DE-1111-2222-3333-444455556666"))
        #expect(board.title == "Front Porch")
        #expect(board.notes == "Greet + heckle")
        #expect(board.tiles.count == 1)
        #expect(board.tiles[0].label == "Greet")
        #expect(board.tiles[0].action == .adHocSpeech(creatureId: "abc", resumePlaylist: true))
        #expect(board.createdAt == 1_748_579_999_000)
        #expect(board.createdAtDate == Date(timeIntervalSince1970: 1_748_579_999.0))
    }

    @Test("encodes id as a lowercase UUID string")
    func encodesLowercaseId() throws {
        let id = UUID()
        let board = Storyboard(id: id, title: "T", notes: "", tiles: [])
        let obj = try encodeToObject(board)
        #expect(obj["id"] as? String == id.uuidString.lowercased())
    }

    @Test("round-trips preserving relative tile coordinates")
    func roundTripsCoordinates() throws {
        let original = Storyboard.mock()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Storyboard.self, from: Data(data))
        #expect(decoded.tiles.count == original.tiles.count)
        for (a, b) in zip(decoded.tiles, original.tiles) {
            #expect(a.x == b.x)
            #expect(a.y == b.y)
            #expect(a.width == b.width)
            #expect(a.height == b.height)
            #expect(a.action == b.action)
        }
    }

    @Test("tile clamps out-of-range coordinates")
    func tileClamps() throws {
        let json = """
            { "id": "11111111-1111-1111-1111-111111111111", "x": 1.5, "y": -0.3,
              "width": 2.0, "height": 0.0, "label": "X", "sf_symbol": "square",
              "tint_color_hex": "#fff", "action": { "type": "play_sound", "file_name": "a.wav" } }
            """
        let tile = try JSONDecoder().decode(StoryboardTile.self, from: Data(json.utf8))
        #expect(tile.x == 1.0)
        #expect(tile.y == 0.0)
        #expect(tile.width == 1.0)
        #expect(tile.height == 0.05)  // clamped to the minimum tappable size
    }

    @Test("upsert request carries only editable fields")
    func upsertOmitsServerFields() throws {
        let obj = try encodeToObject(UpsertStoryboardRequest(Storyboard.mock()))
        #expect(Set(obj.keys) == ["title", "notes", "tiles"])
        #expect(obj["id"] == nil)
        #expect(obj["created_at"] == nil)
    }

    @Test("newEmpty is a usable blank card")
    func newEmptyBlank() {
        let board = Storyboard.newEmpty()
        #expect(board.title.isEmpty)
        #expect(board.tiles.isEmpty)
        #expect(board.createdAt == nil)
    }

    @Test("limits match the server caps")
    func limitsMatchServer() {
        #expect(StoryboardLimits.maxTitle == 256)
        #expect(StoryboardLimits.maxNotes == 16384)
        #expect(StoryboardLimits.maxTiles == 200)
        #expect(StoryboardLimits.maxTileLabel == 256)
    }

    // MARK: - StoryboardAction encoding (one per case)

    private func actionObject(_ action: StoryboardAction) throws -> [String: Any] {
        let data = try JSONEncoder().encode(action)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test("play_animation encodes snake_case with optional universe")
    func encodesPlayAnimation() throws {
        let obj = try actionObject(
            .playAnimation(
                animationId: "anim1", universe: 2, interrupt: true, resumePlaylist: false))
        #expect(obj["type"] as? String == "play_animation")
        #expect(obj["animation_id"] as? String == "anim1")
        #expect(obj["universe"] as? Int == 2)
        #expect(obj["interrupt"] as? Bool == true)
        #expect(obj["resume_playlist"] as? Bool == false)
    }

    @Test("nil universe is omitted")
    func omitsNilUniverse() throws {
        let obj = try actionObject(.stopPlaylist(universe: nil))
        #expect(obj["type"] as? String == "stop_playlist")
        #expect(obj["universe"] == nil)
    }

    @Test("render_dialog encodes a lowercased script_id")
    func encodesRenderDialog() throws {
        let id = UUID()
        let obj = try actionObject(.renderDialog(scriptId: id))
        #expect(obj["type"] as? String == "render_dialog")
        #expect(obj["script_id"] as? String == id.uuidString.lowercased())
    }

    @Test("fixture actions encode their ids")
    func encodesFixtureActions() throws {
        #expect(try actionObject(.fixtureOn(fixtureId: "f1"))["type"] as? String == "fixture_on")
        #expect(try actionObject(.fixtureOff(fixtureId: "f1"))["type"] as? String == "fixture_off")
        #expect(
            try actionObject(.fixtureDetails(fixtureId: "f1"))["type"] as? String
                == "fixture_details")
        let pat = try actionObject(
            .fixturePattern(fixtureId: "f1", patternId: "p1", stopAfterMs: 5000))
        #expect(pat["type"] as? String == "fixture_pattern")
        #expect(pat["pattern_id"] as? String == "p1")
        #expect(pat["stop_after_ms"] as? Int == 5000)
    }

    @Test("every known action round-trips")
    func actionsRoundTrip() throws {
        let actions: [StoryboardAction] = [
            .playAnimation(animationId: "a", universe: nil, interrupt: false, resumePlaylist: true),
            .adHocSpeech(creatureId: "c", resumePlaylist: true),
            .liveControl(creatureId: "c", universe: 2),
            .startPlaylist(playlistId: "p", universe: nil),
            .stopPlaylist(universe: 3),
            .playSound(fileName: "chime.wav"),
            .renderDialog(scriptId: UUID()),
            .fixtureOn(fixtureId: "f"),
            .fixtureOff(fixtureId: "f"),
            .fixturePattern(fixtureId: "f", patternId: "p", stopAfterMs: nil),
            .fixtureDetails(fixtureId: "f"),
        ]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(StoryboardAction.self, from: data)
            #expect(decoded == action)
        }
    }

    // MARK: - Forward compatibility

    @Test("unknown action type is preserved verbatim across a round-trip")
    func unknownActionRoundTrips() throws {
        let json = """
            { "type": "some_future_thing", "foo": 42, "bar": ["x", true], "nested": { "z": 1.5 } }
            """
        let decoded = try JSONDecoder().decode(StoryboardAction.self, from: Data(json.utf8))
        guard case .unknown(let type, let raw) = decoded else {
            Issue.record("expected .unknown, got \(decoded)")
            return
        }
        #expect(type == "some_future_thing")
        #expect(raw["foo"] == .number(42))

        // Re-encode → re-decode: the preserved payload survives.
        let reEncoded = try JSONEncoder().encode(decoded)
        let reDecoded = try JSONDecoder().decode(StoryboardAction.self, from: reEncoded)
        #expect(reDecoded == decoded)
    }
}
