import Foundation
import Testing

@testable import Common

/// A sweep over every model the Console *sends*, asserting none of them writes a JSON `null`.
///
/// Server 3.45.0 rejects an explicit `null` for an optional value, so this is the one property
/// that has to hold across the whole write surface rather than model by model. The audit for
/// console#87 found the remaining models already clean — this suite is what keeps them that
/// way, since a future optional added with a plain `encode` instead of `encodeIfPresent` would
/// fail here rather than in production.
@Suite("Writable models emit no JSON nulls")
struct WritableModelNullSweepTests {

    private let animationId = "aa11bb22-cc33-4d44-8e55-ff6677889900"
    private let creatureId = "5d7c1a02-9b34-4e18-8f6a-2c0d3e5b7a91"
    private let playlistId = "b1c2d3e4-f5a6-4b78-9c01-2d3e4f5a6b7c"
    private let fixtureId = "8e3a4b5c-1d2f-4e6a-9b0c-7f8e9d0a1b2c"

    @Test("a playlist with the minimum item set")
    func playlist() throws {
        let playlist = Playlist(
            id: playlistId,
            name: "Evening Ambience",
            items: [PlaylistItem(animationId: animationId, weight: 1)])

        try NeutralContract.expectNoNulls(playlist, "a playlist")

        let object = try NeutralContract.encodedObject(playlist)
        // The server checks `number_of_items` against the array length, so it has to go out.
        #expect(object["number_of_items"] as? Int == 1)
        #expect(Set(object.keys) == ["id", "name", "items", "number_of_items"])
        #expect(playlist.isValid)
    }

    @Test("a stream frame")
    func streamFrame() throws {
        let frame = StreamFrameData(
            creatureId: creatureId, universe: 1, data: Data([1, 2, 3]).base64EncodedString())

        try NeutralContract.expectNoNulls(frame, "a stream frame")
        let object = try NeutralContract.encodedObject(frame)
        #expect(Set(object.keys) == ["creature_id", "universe", "data"])
    }

    @Test("a fixture with no assigned universe omits it rather than nulling it")
    func fixtureWithoutUniverse() throws {
        let fixture = DmxFixture(
            id: fixtureId,
            name: "Wash Left",
            type: .light,
            channelOffset: 0,
            channels: [
                FixtureChannel(offset: 0, name: "dimmer", kind: FixtureChannelKind.masterDimmer),
                FixtureChannel(offset: 1, name: "red", kind: FixtureChannelKind.colorRed),
            ])

        try NeutralContract.expectNoNulls(fixture, "a fixture with no universe")
        let object = try NeutralContract.encodedObject(fixture)
        #expect(object["assigned_universe"] == nil)
    }

    @Test("a dialog script with no music, take, or stage")
    func bareDialogScript() throws {
        let script = DialogScript(
            id: UUID(),
            title: "Morning Chatter",
            notes: "",
            turns: [DialogScriptTurn(creatureId: creatureId, text: "Good morning!")])

        try NeutralContract.expectNoNulls(script, "a bare dialog script")
        let object = try NeutralContract.encodedObject(script)
        for absent in [
            "background_music", "accepted_voice", "stage_id", "created_at", "updated_at",
        ] {
            #expect(object[absent] == nil, "\(absent) should have been omitted")
        }

        // A turn carries only what the server defines — its client-only `id` never travels.
        let turns = try #require(object["turns"] as? [[String: Any]])
        #expect(Set(turns[0].keys) == ["creature_id", "text"])
    }

    @Test("an animation with nothing optional set")
    func bareAnimation() throws {
        var animation = Animation()
        animation.metadata.title = "Empty"
        animation.tracks = [
            Track(
                id: TrackIdentifier(), creatureId: creatureId, animationId: animation.id,
                frames: [Data([0, 1, 2])])
        ]

        try NeutralContract.expectNoNulls(animation, "a bare animation")
    }

    @Test("a creature with nothing optional set")
    func bareCreature() throws {
        let creature = Creature(
            id: creatureId, name: "Plain", channelOffset: 0, mouthSlot: 1, audioChannel: 1)

        try NeutralContract.expectNoNulls(creature.configurationPayload(), "a bare creature")
        try NeutralContract.expectNoNulls(creature, "a bare creature, full encoding")
    }
}
