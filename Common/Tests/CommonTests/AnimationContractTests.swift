import Foundation
import Testing

@testable import Common

/// Animations against the server 3.45.0 contract (console#87).
///
/// The fixtures here are the six shapes the Console actually meets: creature-only,
/// fixture-only, and mixed tracks; and metadata with no provenance, dialog provenance, and
/// stage provenance. The round-trip assertions matter more than the decode ones — renaming an
/// animation is a fetch, mutate, re-POST, so anything this model can't carry is destroyed the
/// first time somebody renames a rendered scene.
@Suite("Animation server contract")
struct AnimationContractTests {

    private let animationId = "aa11bb22-cc33-4d44-8e55-ff6677889900"
    private let creatureId = "5d7c1a02-9b34-4e18-8f6a-2c0d3e5b7a91"
    private let otherCreatureId = "6e8d2b13-ac45-4f29-9a7b-3d1e4f6c8b02"
    private let fixtureId = "8e3a4b5c-1d2f-4e6a-9b0c-7f8e9d0a1b2c"
    private let stageId = "c9f0a1b2-3d4e-4f50-a617-2839b4c5d6e7"
    private let scriptId = "d0a1b2c3-4e5f-4061-b728-394ac5d6e7f8"

    /// One base64 frame, so `number_of_frames` can be 1 and stay consistent.
    private let frame = "AQIDBAUGBw=="

    private func creatureTrack(id: String, creature: String) -> String {
        """
        {"id": "\(id)", "creature_id": "\(creature)", "animation_id": "\(animationId)",
         "frames": ["\(frame)"]}
        """
    }

    private func fixtureTrack(id: String) -> String {
        """
        {"id": "\(id)", "fixture_id": "\(fixtureId)", "animation_id": "\(animationId)",
         "frames": ["\(frame)"]}
        """
    }

    private func animationJSON(metadata: String, tracks: [String]) -> String {
        """
        {
          "id": "\(animationId)",
          "metadata": \(metadata),
          "tracks": [\(tracks.joined(separator: ","))]
        }
        """
    }

    /// Metadata with nothing optional set at all — note omitted, no provenance. This is what
    /// the server sends for a hand-authored animation, and decoding it used to throw because
    /// `note` was required.
    private var bareMetadata: String {
        """
        {
          "animation_id": "\(animationId)",
          "title": "Hand Built",
          "milliseconds_per_frame": 20,
          "sound_file": "",
          "number_of_frames": 1,
          "multitrack_audio": false
        }
        """
    }

    private var dialogMetadata: String {
        """
        {
          "animation_id": "\(animationId)",
          "title": "Two Birds Talking",
          "milliseconds_per_frame": 20,
          "note": "second take",
          "sound_file": "scenes/two-birds.mp3",
          "number_of_frames": 1,
          "multitrack_audio": true,
          "source_script_id": "\(scriptId)",
          "source_script_turns": [
            {"creature_id": "\(creatureId)", "text": "Did you hear that?"},
            {"creature_id": "\(otherCreatureId)", "text": "[whispering] I did."}
          ],
          "render_seed": 8675309,
          "source_render_choices": [
            {
              "creature_id": "\(creatureId)",
              "speech_loop_animation_id": "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d",
              "idle_animation_id": "3c4d5e6f-7a8b-4c9d-0e1f-2a3b4c5d6e7f",
              "idle_start_offset": 42
            },
            {
              "creature_id": "\(otherCreatureId)",
              "speech_loop_animation_id": "2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e"
            }
          ]
        }
        """
    }

    private var stageMetadata: String {
        """
        {
          "animation_id": "\(animationId)",
          "title": "On The Mainstage",
          "milliseconds_per_frame": 20,
          "sound_file": "scenes/mainstage.mp3",
          "number_of_frames": 1,
          "multitrack_audio": true,
          "source_stage_id": "\(stageId)",
          "source_stage_updated_at": 1770000000000,
          "source_stage_placements": [
            {
              "creature_id": "\(creatureId)",
              "x": -1.5, "y": -0.25, "z": -2.0, "yaw": 15.0,
              "creature_name": "Beaky", "audio_channel": 1, "gain": 1.0, "muted": false,
              "future_client_key": "preserved"
            }
          ]
        }
        """
    }

    private func decode(_ json: String) throws -> Animation {
        try JSONDecoder().decode(Animation.self, from: Data(json.utf8))
    }

    /// Decode, re-encode, decode again — the shape of a rename.
    private func roundTrip(_ animation: Animation) throws -> Animation {
        let data = try JSONEncoder().encode(animation)
        return try JSONDecoder().decode(Animation.self, from: data)
    }

    // MARK: Track shapes

    @Test("a creature-only animation round-trips")
    func creatureOnlyAnimation() throws {
        let animation = try decode(
            animationJSON(
                metadata: bareMetadata,
                tracks: [creatureTrack(id: UUID().uuidString, creature: creatureId)]))

        #expect(animation.tracks.count == 1)
        #expect(animation.tracks[0].creatureId == creatureId)
        #expect(try roundTrip(animation) == animation)
        try NeutralContract.expectNoNulls(animation, "a creature-only animation")
    }

    /// The server omits `creature_id` entirely for a fixture track. This whole animation used
    /// to fail to decode because of it.
    @Test("a fixture-only animation round-trips")
    func fixtureOnlyAnimation() throws {
        let animation = try decode(
            animationJSON(
                metadata: bareMetadata, tracks: [fixtureTrack(id: UUID().uuidString)]))

        #expect(animation.tracks.count == 1)
        #expect(animation.tracks[0].fixtureId == fixtureId)
        #expect(animation.tracks[0].creatureId == nil)
        #expect(try roundTrip(animation) == animation)

        // And on the way back out, no empty-string placeholder for the owner it doesn't have.
        let object = try NeutralContract.encodedObject(animation)
        let track = try #require((object["tracks"] as? [[String: Any]])?.first)
        #expect(track["creature_id"] == nil)
        try NeutralContract.expectNoNulls(animation, "a fixture-only animation")
    }

    @Test("a mixed creature-and-fixture animation round-trips")
    func mixedAnimation() throws {
        let animation = try decode(
            animationJSON(
                metadata: bareMetadata,
                tracks: [
                    creatureTrack(id: UUID().uuidString, creature: creatureId),
                    creatureTrack(id: UUID().uuidString, creature: otherCreatureId),
                    fixtureTrack(id: UUID().uuidString),
                ]))

        #expect(animation.tracks.count == 3)
        #expect(animation.tracks.compactMap(\.creatureId).count == 2)
        #expect(animation.tracks.compactMap(\.fixtureId).count == 1)
        #expect(try roundTrip(animation) == animation)
        try NeutralContract.expectNoNulls(animation, "a mixed animation")
    }

    // MARK: Metadata provenance

    @Test("metadata with no provenance decodes and stays empty")
    func noProvenance() throws {
        let animation = try decode(
            animationJSON(
                metadata: bareMetadata,
                tracks: [creatureTrack(id: UUID().uuidString, creature: creatureId)]))
        let metadata = animation.metadata

        #expect(metadata.note.isEmpty)
        #expect(metadata.sourceScriptId == nil)
        #expect(metadata.sourceScriptTurns == nil)
        #expect(metadata.sourceStageId == nil)
        #expect(metadata.sourceStageUpdatedAt == nil)
        #expect(metadata.sourceStagePlacements == nil)
        #expect(metadata.renderSeed == nil)
        #expect(metadata.sourceRenderChoices == nil)
        #expect(!metadata.hasDialogProvenance)

        // Nothing optional comes back out, and `last_updated` — a key the server has never
        // had, and now rejects — is gone for good.
        let object = try NeutralContract.encodedObject(metadata)
        for absent in [
            "note", "last_updated", "source_script_id", "source_script_turns", "source_stage_id",
            "source_stage_updated_at", "source_stage_placements", "render_seed",
            "source_render_choices",
        ] {
            #expect(object[absent] == nil, "\(absent) should have been omitted")
        }
    }

    @Test("dialog provenance survives a round trip")
    func dialogProvenance() throws {
        let animation = try decode(
            animationJSON(
                metadata: dialogMetadata,
                tracks: [creatureTrack(id: UUID().uuidString, creature: creatureId)]))
        let metadata = animation.metadata

        #expect(metadata.sourceScriptIdentifier == UUID(uuidString: scriptId))
        #expect(metadata.sourceScriptTurns?.count == 2)
        #expect(metadata.hasDialogProvenance)
        #expect(metadata.renderSeed == 8_675_309)
        #expect(metadata.sourceRenderChoices?.count == 2)
        #expect(metadata.sourceRenderChoices?[0].idleStartOffset == 42)
        // The second choice had no idle loop, and doesn't gain one.
        #expect(metadata.sourceRenderChoices?[1].idleAnimationId == nil)
        #expect(metadata.sourceRenderChoices?[1].idleStartOffset == nil)

        let again = try roundTrip(animation)
        #expect(again == animation)
        #expect(again.metadata.renderSeed == 8_675_309)
        #expect(again.metadata.sourceRenderChoices == metadata.sourceRenderChoices)
        try NeutralContract.expectNoNulls(animation, "a dialog-provenance animation")

        // The render choice with no idle loop encodes without placeholder keys.
        let object = try NeutralContract.encodedObject(metadata)
        let choices = try #require(object["source_render_choices"] as? [[String: Any]])
        #expect(choices[1]["idle_animation_id"] == nil)
        #expect(choices[1]["idle_start_offset"] == nil)
    }

    @Test("stage provenance survives a round trip, including Console-owned placement keys")
    func stageProvenance() throws {
        let animation = try decode(
            animationJSON(
                metadata: stageMetadata,
                tracks: [creatureTrack(id: UUID().uuidString, creature: creatureId)]))
        let metadata = animation.metadata

        #expect(metadata.sourceStageIdentifier == UUID(uuidString: stageId))
        #expect(metadata.sourceStageUpdatedAt == 1_770_000_000_000)
        #expect(metadata.sourceStagePlacements?.count == 1)
        #expect(metadata.sourceStagePlacements?[0].creatureName == "Beaky")

        let again = try roundTrip(animation)
        #expect(again == animation)
        #expect(again.metadata.sourceStagePlacements == metadata.sourceStagePlacements)

        // A placement key written by a newer client rides along untouched.
        let object = try NeutralContract.encodedObject(metadata)
        let placements = try #require(object["source_stage_placements"] as? [[String: Any]])
        #expect(placements[0]["future_client_key"] as? String == "preserved")
        try NeutralContract.expectNoNulls(animation, "a stage-provenance animation")
    }

    /// The server rejects `source_stage_id` without `source_stage_updated_at`, and vice versa,
    /// so a half-set pair must never go out.
    @Test("a half-set stage pointer is not encoded")
    func halfSetStagePointerIsOmitted() throws {
        var metadata = try decode(
            animationJSON(
                metadata: bareMetadata,
                tracks: [creatureTrack(id: UUID().uuidString, creature: creatureId)])
        ).metadata

        metadata.sourceStageId = stageId  // ...but no updated_at
        var object = try NeutralContract.encodedObject(metadata)
        #expect(object["source_stage_id"] == nil)
        #expect(object["source_stage_updated_at"] == nil)

        metadata.sourceStageUpdatedAt = 1_770_000_000_000
        object = try NeutralContract.encodedObject(metadata)
        #expect(object["source_stage_id"] as? String == stageId)
        #expect(object["source_stage_updated_at"] as? Int64 == 1_770_000_000_000)
    }

    /// The bug this whole thing started from: rename an animation, lose its provenance.
    @Test("renaming a rendered animation keeps its provenance")
    func renamingKeepsProvenance() throws {
        var animation = try decode(
            animationJSON(
                metadata: stageMetadata,
                tracks: [creatureTrack(id: UUID().uuidString, creature: creatureId)]))

        animation.metadata.title = "On The Mainstage (v2)"
        let saved = try roundTrip(animation)

        #expect(saved.metadata.title == "On The Mainstage (v2)")
        #expect(saved.metadata.sourceStageId == stageId)
        #expect(saved.metadata.sourceStageUpdatedAt == 1_770_000_000_000)
        #expect(saved.metadata.sourceStagePlacements?.count == 1)
    }
}
