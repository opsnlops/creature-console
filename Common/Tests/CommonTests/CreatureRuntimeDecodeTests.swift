import Foundation
import Testing

@testable import Common

@Suite("Creature runtime decoding")
struct CreatureRuntimeDecodeTests {

    @Test("Decodes runtime activity with ISO8601 timestamps")
    func decodesRuntimeActivity() throws {
        let json = """
            {
              "id": "creature-1",
              "name": "Testy",
              "channel_offset": 1,
              "audio_channel": 2,
              "mouth_slot": 3,
              "inputs": [],
              "speech_loop_animation_ids": [],
              "idle_animation_ids": [],
              "runtime": {
                "idle_enabled": true,
                "activity": {
                  "state": "idle",
                  "animation_id": null,
                  "session_id": null,
                  "reason": "play",
                  "started_at": "2025-12-09T05:19:07Z",
                  "updated_at": "2025-12-09T05:19:07Z"
                },
                "counters": {
                  "sessions_started_total": 1,
                  "sessions_cancelled_total": 0,
                  "idle_started_total": 0,
                  "idle_stopped_total": 0,
                  "idle_toggles_total": 0,
                  "skips_missing_creature_total": 0,
                  "bgm_takeovers_total": 0,
                  "audio_resets_total": 0
                },
                "bgm_owner": null,
                "last_error": null
              }
            }
            """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let creature = try decoder.decode(Creature.self, from: Data(json.utf8))

        #expect(creature.runtime?.idleEnabled == true)
        let activity = try #require(creature.runtime?.activity)
        #expect(activity.state == .idle)
        #expect(activity.reason == .play)
        #expect(activity.animationId == nil)
        #expect(activity.sessionId == nil)

        let formatter = ISO8601DateFormatter()
        let expectedDate = formatter.date(from: "2025-12-09T05:19:07Z")
        #expect(activity.startedAt == expectedDate)
        #expect(activity.updatedAt == expectedDate)
    }
}
