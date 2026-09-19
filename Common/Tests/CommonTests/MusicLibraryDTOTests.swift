import Foundation
import Testing

@testable import Common

@Suite("Music library DTOs")
struct MusicLibraryDTOTests {

    private func chunk(_ text: String, _ ms: Int64, styles: [String] = []) -> MusicGenerationChunk {
        MusicGenerationChunk(text: text, durationMilliseconds: ms, positiveStyles: styles)
    }

    private func json(_ encodable: some Encodable) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(encodable))
                as? [String: Any])
    }

    @Test("prompt-mode generate sends an explicit length and no dialog fields")
    func promptGenerate() throws {
        let request = MusicGenerateRequest(
            composition: .prompt(
                DialogMusicRequest.Prompt(
                    prompt: "Bright", generationMode: .loop, forceInstrumental: false),
                musicLengthMilliseconds: 30_000))
        let object = try json(request)
        #expect(object["prompt"] as? String == "Bright")
        #expect(object["music_length_ms"] as? Int == 30_000)
        #expect(object["generation_mode"] as? String == "loop")
        #expect(object["force_instrumental"] as? Bool == false)
        #expect(object["model_id"] as? String == "music_v2_5")
        #expect(object["script_id"] == nil)
        #expect(object["sections"] == nil)
        #expect(object["keep"] == nil)
        #expect(request.requestKind == .prompt)
    }

    @Test("sections-mode generate sends sections, base, keep and strength, never conditioning")
    func sectionsGenerate() throws {
        let pieceId = UUID()
        let baseId = UUID()
        var conditioned = chunk("[Verse]", 10_000, styles: ["brass"])
        conditioned.conditioningReference = MusicAudioRange(
            songId: "x", startMilliseconds: 0, endMilliseconds: 3_000)
        conditioned.conditionStrength = .high
        let request = MusicGenerateRequest(
            composition: .sections(
                [chunk("[Intro]", 5_000), conditioned], baseVersionId: baseId, keep: [0],
                conditionStrength: .medium, seed: 21),
            pieceId: pieceId,
            finetune: MusicFinetuneSelection(finetuneId: "ft", strength: 0.5))
        let object = try json(request)
        #expect(object["piece_id"] as? String == pieceId.uuidString.lowercased())
        #expect(object["base_version_id"] as? String == baseId.uuidString.lowercased())
        #expect(object["keep"] as? [Int] == [0])
        #expect(object["condition_strength"] as? String == "medium")
        #expect(object["seed"] as? Int == 21)
        #expect(object["finetune_id"] as? String == "ft")
        let sections = try #require(object["sections"] as? [[String: Any]])
        #expect(sections.count == 2)
        #expect(sections[1]["conditioning_ref"] == nil)
        #expect(sections[1]["condition_strength"] == nil)
        #expect(object["prompt"] == nil)
        #expect(object["composition_plan"] == nil)
        #expect(request.requestKind == .sections)
    }

    @Test("an empty keep list is omitted")
    func emptyKeepOmitted() throws {
        let request = MusicGenerateRequest(
            composition: .sections(
                [chunk("a", 5_000)], baseVersionId: nil, keep: [], conditionStrength: nil, seed: nil
            ))
        let object = try json(request)
        #expect(object["keep"] == nil)
        #expect(object["base_version_id"] == nil)
        #expect(object["condition_strength"] == nil)
    }

    @Test("save, update, refine and plan requests encode their contracts")
    func smallRequests() throws {
        let pieceId = UUID()
        let save = try json(
            MusicSaveRequest(
                title: "Parrot Parade", pieceId: pieceId, sections: [chunk("a", 5_000)]))
        #expect(save["title"] as? String == "Parrot Parade")
        #expect(save["piece_id"] as? String == pieceId.uuidString.lowercased())
        #expect((save["sections"] as? [[String: Any]])?.count == 1)
        #expect(save["notes"] == nil)

        let versionId = UUID()
        let update = try json(MusicPieceUpdateRequest(currentVersionId: versionId))
        #expect(update["current_version_id"] as? String == versionId.uuidString.lowercased())
        #expect(update["title"] == nil)

        let refine = try json(
            MusicRefineRequest(instruction: "add smooth synth pads", versionId: versionId))
        #expect(refine["instruction"] as? String == "add smooth synth pads")
        #expect(refine["version_id"] as? String == versionId.uuidString.lowercased())

        let plan = try json(MusicPlanRequest(prompt: "Bright", musicLengthMilliseconds: 30_000))
        #expect(plan["music_length_ms"] as? Int == 30_000)
        #expect(plan["model_id"] as? String == "music_v2_5")
        #expect(plan["source_sections"] == nil)
    }

    @Test("refine and plan results decode")
    func resultsDecode() throws {
        let baseId = UUID()
        let refine = """
            {"base_version_id": "\(baseId.uuidString.lowercased())", "model_id": "music_v2_5",
             "music_length_ms": 30000,
             "sections": [{"text": "[Intro]", "duration_ms": 6000, "positive_styles": [], "negative_styles": [], "context_adherence": "high"},
                          {"text": "[Verse]", "duration_ms": 24000, "positive_styles": ["pads"], "negative_styles": [], "context_adherence": "high"}],
             "changed": [1], "kept": [0], "composition_plan": {"chunks": []}}
            """
        let result = try JSONDecoder().decode(MusicRefineResult.self, from: Data(refine.utf8))
        #expect(result.baseVersionId == baseId)
        #expect(result.sections.count == 2)
        #expect(result.changed == [1])
        #expect(result.kept == [0])

        let plan = """
            {"model_id": "music_v2_5", "music_length_ms": 9000,
             "sections": [{"text": "[Theme]", "duration_ms": 9000}], "composition_plan": {"chunks": []}}
            """
        let planned = try JSONDecoder().decode(MusicPlanResult.self, from: Data(plan.utf8))
        #expect(planned.sections.first?.text == "[Theme]")
        #expect(planned.musicLengthMilliseconds == 9_000)
    }

    @Test("a saved piece decodes the prod shape, with a sections recipe and a null-bearing plan")
    func savedPieceDecodes() throws {
        let json = """
            {"created_at": 1789798557188, "current_version_id": "7bef5d2d-f269-42e6-af92-e045abaecd6f",
             "id": "7fece0f6-1d09-4d24-bce5-a6c4aa2bff88", "notes": "library test", "title": "Parrot Parade",
             "updated_at": 1789800257473,
             "versions": [
               {"created_at": 1789798557188, "duration_ms": 30000, "id": "7bef5d2d-f269-42e6-af92-e045abaecd6f",
                "mp3_url": "/api/v1/sound/mp3/parrot-parade--7bef5d2d-f26.mp3", "song_id": "song-1",
                "sound_file": "music/parrot-parade--7bef5d2d-f26.wav",
                "recipe": {"model_id": "music_v2_5", "song_id": "song-1", "request_kind": "sections", "seed": 21,
                           "stored_for_inpainting": true, "piece_id": "7fece0f6-1d09-4d24-bce5-a6c4aa2bff88",
                           "sections": [{"text": "[Intro]", "duration_ms": 30000}],
                           "composition_plan": {"chunks": [{"text": "[Intro]", "duration_ms": 30000, "positive_styles": [],
                                                            "negative_styles": [], "context_adherence": "high",
                                                            "conditioning_ref": null, "condition_strength": null}]},
                           "song_metadata": {}},
                "sections": [{"text": "[Intro]", "duration_ms": 30000, "positive_styles": ["85 BPM"], "negative_styles": ["drums"], "context_adherence": "high"}]},
               {"created_at": 1789800257385, "duration_ms": 30000, "id": "9d404ab4-fe70-4baf-9f53-c3085390e33a",
                "base_version_id": "7bef5d2d-f269-42e6-af92-e045abaecd6f",
                "mp3_url": "/api/v1/sound/mp3/parrot-parade--9d404ab4-fe7.mp3", "song_id": "song-2",
                "sound_file": "music/parrot-parade--9d404ab4-fe7.wav", "recipe": {},
                "sections": [{"text": "[Intro]", "duration_ms": 30000}],
                "source_dialog": {"script_id": "5d9e00b0-a538-4bb1-a096-c856ac982dac",
                                  "dialog_cache_key": "abc", "dialog_generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2"}}
             ]}
            """
        let piece = try JSONDecoder().decode(SavedMusicPiece.self, from: Data(json.utf8))
        #expect(piece.title == "Parrot Parade")
        #expect(piece.versions.count == 2)
        #expect(
            piece.currentVersion?.id == UUID(uuidString: "7bef5d2d-f269-42e6-af92-e045abaecd6f"))
        let first = piece.versions[0]
        #expect(first.recipe?.requestKind == .sections)
        #expect(first.recipe?.seed == 21)
        #expect(first.recipe?.pieceId == piece.id)
        #expect(first.recipe?.sections?.count == 1)
        #expect(first.recipe?.compositionPlan?.chunks.count == 1)
        #expect(first.sections.first?.positiveStyles == ["85 BPM"])
        #expect(first.canBeReferenced)
        let second = piece.versions[1]
        #expect(second.recipe == nil)
        #expect(second.baseVersionId == first.id)
        #expect(second.sourceDialog?.dialogCacheKey == "abc")

        // Round trip through our own encoder.
        let reparsed = try JSONDecoder().decode(
            SavedMusicPiece.self, from: try JSONEncoder().encode(piece))
        #expect(reparsed == piece)
    }

    @Test("a dangling or empty current pointer falls back to the newest version")
    func currentFallback() throws {
        let json = """
            {"id": "7fece0f6-1d09-4d24-bce5-a6c4aa2bff88", "title": "x", "created_at": 1, "updated_at": 2,
             "current_version_id": "",
             "versions": [
               {"id": "7bef5d2d-f269-42e6-af92-e045abaecd6f", "song_id": "a", "sound_file": "f", "mp3_url": "m", "duration_ms": 3000, "recipe": {}, "sections": [], "created_at": 10},
               {"id": "9d404ab4-fe70-4baf-9f53-c3085390e33a", "song_id": "b", "sound_file": "f", "mp3_url": "m", "duration_ms": 3000, "recipe": {}, "sections": [], "created_at": 20}
             ]}
            """
        let piece = try JSONDecoder().decode(SavedMusicPiece.self, from: Data(json.utf8))
        #expect(piece.currentVersionId == nil)
        #expect(piece.currentVersion?.songId == "b")
    }

    @Test("the music cache type and job type decode")
    func newKinds() throws {
        struct Wrapper: Decodable { let cache_type: CacheType }
        let wrapper = try JSONDecoder().decode(
            Wrapper.self, from: Data(#"{"cache_type":"music-piece-list"}"#.utf8))
        #expect(wrapper.cache_type == .musicPieceList)
        #expect(JobType(rawValue: "music") == .music)
    }
}

@Suite("Music pieces and the library")
struct MusicPieceLibraryTests {

    private func chunk(_ text: String, _ ms: Int64, styles: [String] = []) -> MusicGenerationChunk {
        MusicGenerationChunk(text: text, durationMilliseconds: ms, positiveStyles: styles)
    }

    private func version(songId: String = "song-A") -> SavedMusicVersion {
        SavedMusicVersion(
            id: UUID(), songId: songId, soundFile: "music/x.wav", mp3Url: "/api/v1/sound/mp3/x.mp3",
            durationMilliseconds: 20_000,
            sections: [
                chunk("[Intro]", 5_000, styles: ["a"]), chunk("[Verse]", 10_000),
                chunk("[Outro]", 5_000),
            ],
            createdAt: 1)
    }

    @Test("a saved version becomes a clean piece with spans in its song")
    func pieceFromVersion() {
        let piece = MusicPiece(version: version())
        #expect(!piece.isDirty)
        #expect(piece.songId == "song-A")
        #expect(piece.sections.map { $0.span?.startMilliseconds } == [0, 5_000, 15_000])
        #expect(piece.serverSections == version().sections)
    }

    @Test("kept indices are the clean sections that still sit where the base had them")
    func keptIndices() {
        let base = version()
        var piece = MusicPiece(version: base)
        #expect(piece.keptIndices(against: base.sections) == [0, 1, 2])

        piece.sections[1].content.positiveStyles.append("pads")
        #expect(piece.keptIndices(against: base.sections) == [0, 2])

        // Insert a section: everything after it moves and can no longer be kept by index.
        piece.insertSection(chunk("[Bridge]", 4_000), at: 1)
        #expect(piece.keptIndices(against: base.sections) == [0])
    }

    @Test("committing to a saved version moves sections onto its song, or adopts the record")
    func committedToVersion() {
        let base = version()
        var piece = MusicPiece(version: base)
        piece.sections[1].content.text = "[Verse] louder"
        let saved = SavedMusicVersion(
            id: UUID(), songId: "song-B", soundFile: "f", mp3Url: "m", durationMilliseconds: 20_000,
            sections: piece.serverSections, baseVersionId: base.id, createdAt: 2)
        let next = piece.committed(version: saved)
        #expect(!next.isDirty)
        #expect(next.songId == "song-B")
        #expect(next.sections[1].content.text == "[Verse] louder")
        #expect(next.sections[1].id == piece.sections[1].id)

        let disagreeing = SavedMusicVersion(
            id: UUID(), songId: "song-C", soundFile: "f", mp3Url: "m", durationMilliseconds: 9_000,
            sections: [chunk("[All]", 9_000)], createdAt: 3)
        let adopted = piece.committed(version: disagreeing)
        #expect(adopted.sections.count == 1)
        #expect(adopted.songId == "song-C")
    }

    @Test("a refine proposal lays over the piece and marks only what differs")
    func applyingProposal() {
        let base = version()
        let piece = MusicPiece(version: base)
        let proposal = [
            chunk("[Intro]", 5_000, styles: ["a"]),
            chunk("[Verse]", 10_000, styles: ["smooth synth pads"]),
            chunk("[Outro]", 5_000),
            chunk("[Coda]", 4_000),
        ]
        let proposed = piece.applying(proposal: proposal)
        #expect(proposed.sections.count == 4)
        #expect(proposed.sections.map(\.isDirty) == [false, true, false, true])
        #expect(proposed.sections[0].id == piece.sections[0].id)
        #expect(proposed.keptIndices(against: base.sections) == [0, 2])
        #expect(proposed.plannedDurationMilliseconds == 24_000)
    }
}
