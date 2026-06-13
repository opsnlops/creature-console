import CreatureMigration
import MongoKitten
import Testing

@Suite("ContentReferences tests")
struct ContentReferencesTests {

    // MARK: - Storyboards

    private func storyboard(tiles: [Document]) -> Document {
        var tileArray = Document(isArray: true)
        for tile in tiles { tileArray.append(tile) }
        return ["id": "sb-1", "title": "Test", "tiles": tileArray]
    }

    private func tile(action: Document) -> Document {
        ["id": "tile-1", "action": action]
    }

    @Test("extracts a play_animation reference from a storyboard")
    func playAnimation() {
        let sb = storyboard(tiles: [
            tile(action: ["type": "play_animation", "animation_id": "anim-uuid", "interrupt": true])
        ])
        #expect(
            ContentReferences.references(in: sb, collection: "storyboards") == [
                EntityReference(kind: .animation, identifier: "anim-uuid", origin: "play_animation")
            ])
    }

    @Test("maps every known storyboard reference key to the right kind")
    func allReferenceKinds() {
        let sb = storyboard(tiles: [
            tile(action: ["type": "play_animation", "animation_id": "a"]),
            tile(action: ["type": "ad_hoc_speech", "creature_id": "c"]),
            tile(action: ["type": "start_playlist", "playlist_id": "p"]),
            tile(action: ["type": "render_dialog", "script_id": "s"]),
            tile(action: ["type": "fixture_on", "fixture_id": "f"]),
            tile(action: ["type": "play_sound", "file_name": "noise.wav"]),
        ])
        let refs = ContentReferences.references(in: sb, collection: "storyboards")
        #expect(refs.count == 6)
        #expect(refs.first { $0.kind == .animation }?.identifier == "a")
        #expect(refs.first { $0.kind == .creature }?.identifier == "c")
        #expect(refs.first { $0.kind == .playlist }?.identifier == "p")
        #expect(refs.first { $0.kind == .dialogScript }?.identifier == "s")
        #expect(refs.first { $0.kind == .fixture }?.identifier == "f")
        #expect(refs.first { $0.kind == .sound }?.identifier == "noise.wav")
    }

    @Test("storyboard tiles without an action, or with empty ids, are skipped")
    func storyboardDefensiveParsing() {
        let sb = storyboard(tiles: [
            ["id": "no-action"],
            tile(action: ["type": "stop_playlist"]),
            tile(action: ["type": "play_animation", "animation_id": ""]),
        ])
        #expect(ContentReferences.references(in: sb, collection: "storyboards").isEmpty)
    }

    // MARK: - Dialog scripts

    private func dialogScript(turns: [Document]) -> Document {
        var turnArray = Document(isArray: true)
        for turn in turns { turnArray.append(turn) }
        return ["id": "ds-1", "title": "Scene", "turns": turnArray]
    }

    @Test("extracts a creature reference from each dialog turn")
    func dialogTurnsReferenceCreatures() {
        let ds = dialogScript(turns: [
            ["creature_id": "mango", "text": "Hello"],
            ["creature_id": "beaky", "text": "Hi"],
        ])
        let refs = ContentReferences.references(in: ds, collection: "dialog_scripts")
        #expect(
            refs == [
                EntityReference(kind: .creature, identifier: "mango", origin: "dialog turn"),
                EntityReference(kind: .creature, identifier: "beaky", origin: "dialog turn"),
            ])
    }

    @Test("dialog turns without a creature_id are skipped")
    func dialogDefensiveParsing() {
        let ds = dialogScript(turns: [
            ["text": "narration with no speaker"],
            ["creature_id": "", "text": "empty id"],
        ])
        #expect(ContentReferences.references(in: ds, collection: "dialog_scripts").isEmpty)
    }

    // MARK: - General

    @Test("collection mapping matches the schema (sounds have none)")
    func collectionMapping() {
        #expect(EntityReference.Kind.animation.collection == "animations")
        #expect(EntityReference.Kind.creature.collection == "creatures")
        #expect(EntityReference.Kind.playlist.collection == "playlists")
        #expect(EntityReference.Kind.dialogScript.collection == "dialog_scripts")
        #expect(EntityReference.Kind.fixture.collection == "fixtures")
        #expect(EntityReference.Kind.sound.collection == nil)
    }

    @Test("collections that don't bear references return nothing")
    func nonReferenceBearingCollections() {
        let doc: Document = ["id": "a", "metadata": ["title": "x"] as Document]
        #expect(ContentReferences.references(in: doc, collection: "animations").isEmpty)
        #expect(ContentReferences.references(in: doc, collection: "creatures").isEmpty)
    }
}
