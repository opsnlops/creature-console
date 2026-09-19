import Foundation
import Testing

@testable import Common

@Suite("Dialog music DTOs")
struct DialogMusicDTOTests {
    @Test("request encodes the complete server contract")
    func requestEncoding() throws {
        let scriptId = UUID()
        let dialogGenerationId = UUID()
        let request = DialogMusicRequest(
            scriptId: scriptId,
            dialogCacheKey: String(repeating: "a", count: 64),
            dialogGenerationId: dialogGenerationId,
            prompt: "A gentle instrumental outro",
            durationExtensionMilliseconds: 3_500,
            generationMode: .ambience)

        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["script_id"] as? String == scriptId.uuidString.lowercased())
        #expect(
            json["dialog_generation_id"] as? String
                == dialogGenerationId.uuidString.lowercased())
        #expect(json["duration_extension_ms"] as? Int == 3_500)
        #expect(json["generation_mode"] as? String == "ambience")
        #expect(json["force_instrumental"] as? Bool == true)
        #expect(json["model_id"] as? String == "music_v2_5")
        #expect(json["store_for_inpainting"] as? Bool == true)
        // Plan-only keys never ride along with a prompt: the server rejects the mix.
        #expect(json["seed"] == nil)
        #expect(json["composition_plan"] == nil)
        #expect(json["finetune_id"] == nil)
        #expect(request.requestKind == .prompt)
        #expect(request.generationMode == .ambience)
        #expect(request.compositionPlan == nil)
    }

    @Test("plan-mode request sends only plan keys, plus the common knobs")
    func planRequestEncoding() throws {
        let plan = MusicCompositionPlan(chunks: [
            .audioReference(
                MusicAudioRange(songId: "song-1", startMilliseconds: 0, endMilliseconds: 4_000)),
            .generation(MusicGenerationChunk(text: "[Reveal]", durationMilliseconds: 4_720)),
        ])
        let request = DialogMusicRequest(
            scriptId: UUID(), dialogCacheKey: "k", dialogGenerationId: UUID(),
            composition: .plan(plan, seed: 4_242),
            modelId: .v2,
            finetune: MusicFinetuneSelection(finetuneId: "ft-1", strength: 1.5),
            storeForInpainting: false)

        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["seed"] as? Int == 4_242)
        #expect(json["model_id"] as? String == "music_v2")
        #expect(json["finetune_id"] as? String == "ft-1")
        #expect(json["finetune_strength"] as? Double == 1.5)
        #expect(json["store_for_inpainting"] as? Bool == false)
        let chunks = try #require(
            (json["composition_plan"] as? [String: Any])?["chunks"] as? [[String: Any]])
        #expect(chunks.count == 2)
        #expect(chunks[1]["duration_ms"] as? Int == 4_720)
        #expect(json["prompt"] == nil)
        #expect(json["duration_extension_ms"] == nil)
        #expect(json["generation_mode"] == nil)
        #expect(json["force_instrumental"] == nil)
        #expect(request.requestKind == .compositionPlan)
        #expect(request.prompt == nil)
        #expect(request.seed == 4_242)
    }

    @Test("a plan-mode request without a seed omits the key")
    func planRequestWithoutSeed() throws {
        let request = DialogMusicRequest(
            scriptId: UUID(), dialogCacheKey: "k", dialogGenerationId: UUID(),
            composition: .plan(
                MusicCompositionPlan(chunks: [
                    .generation(MusicGenerationChunk(text: "x", durationMilliseconds: 5_000))
                ]), seed: nil))
        let json = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["seed"] == nil)
    }

    @Test("generation result carries the 3.47 recipe beside the legacy keys")
    func resultWithRecipe() throws {
        let json = """
            {
              "music_generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
              "mp3_url": "/api/v1/animation/dialog/music/generated/take.mp3",
              "duration_seconds": 44.25,
              "dialog_duration_ms": 39500,
              "duration_extension_ms": 5000,
              "requested_music_length_ms": 44500,
              "prompt": "",
              "model_id": "music_v2_5",
              "song_id": "song-abc",
              "request_kind": "composition_plan",
              "seed": 4242,
              "finetune_id": "ft-1",
              "finetune_strength": 0.5,
              "stored_for_inpainting": true,
              "composition_plan": {"chunks": [
                {"text": "[Intro]", "duration_ms": 44500, "positive_styles": ["harp"],
                 "negative_styles": [], "context_adherence": "high",
                 "conditioning_ref": null, "condition_strength": null}
              ]},
              "song_metadata": {"title": "Reveal", "genres": ["orchestral", "playful"], "is_explicit": false}
            }
            """
        let result = try JSONDecoder().decode(
            DialogMusicGenerationResult.self, from: Data(json.utf8))
        let recipe = try #require(result.recipe)
        #expect(recipe.model == .v2_5)
        #expect(recipe.songId == "song-abc")
        #expect(recipe.requestKind == .compositionPlan)
        #expect(recipe.prompt == nil)
        #expect(recipe.generationMode == nil)
        #expect(recipe.seed == 4_242)
        #expect(recipe.finetune == MusicFinetuneSelection(finetuneId: "ft-1", strength: 0.5))
        #expect(recipe.canBeReferenced)
        #expect(recipe.compositionPlan?.chunks.count == 1)
        #expect(recipe.songTitle == "Reveal")
        #expect(recipe.genres == ["orchestral", "playful"])
        #expect(result.durationMilliseconds == 44_250)

        // Round trip keeps the recipe.
        let reparsed = try JSONDecoder().decode(
            DialogMusicGenerationResult.self, from: try JSONEncoder().encode(result))
        #expect(reparsed == result)
    }

    @Test("a prompt-mode recipe with an empty plan object decodes with no plan")
    func recipeWithoutPlan() throws {
        let json = """
            {"model_id": "music_v2_5", "song_id": "s", "request_kind": "prompt",
             "prompt": "Warm strings", "generation_mode": "loop", "force_instrumental": false,
             "stored_for_inpainting": false, "composition_plan": {}, "song_metadata": {}}
            """
        let recipe = try JSONDecoder().decode(DialogMusicRecipe.self, from: Data(json.utf8))
        #expect(recipe.compositionPlan == nil)
        #expect(recipe.prompt == "Warm strings")
        #expect(recipe.generationMode == .loop)
        #expect(recipe.forceInstrumental == false)
        #expect(!recipe.canBeReferenced)
        #expect(recipe.songMetadata.isEmpty)
    }

    @Test("a recipe with a malformed plan is an error, not a silent nil")
    func recipeRejectsBrokenPlan() {
        let json = """
            {"model_id": "music_v2_5", "song_id": "s", "request_kind": "prompt",
             "composition_plan": {"chunks": [{"duration_ms": 3000}]}}
            """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DialogMusicRecipe.self, from: Data(json.utf8))
        }
    }

    @Test("legacy seven-key result still decodes with no recipe")
    func legacyResultHasNoRecipe() throws {
        let json = """
            {"music_generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2", "mp3_url": "/x.mp3",
             "duration_seconds": 4, "dialog_duration_ms": 3000, "duration_extension_ms": 0,
             "requested_music_length_ms": 4000, "prompt": "p"}
            """
        let result = try JSONDecoder().decode(
            DialogMusicGenerationResult.self, from: Data(json.utf8))
        #expect(result.recipe == nil)
        #expect(result.prompt == "p")
    }

    @Test("plan request encodes the server contract and omits an absent source plan")
    func planRequestContract() throws {
        let generationId = UUID()
        let request = DialogMusicPlanRequest(
            dialogCacheKey: "k", dialogGenerationId: generationId, prompt: "Bright",
            durationExtensionMilliseconds: 2_000, modelId: .v2_5)
        let json = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["dialog_generation_id"] as? String == generationId.uuidString.lowercased())
        #expect(json["prompt"] as? String == "Bright")
        #expect(json["duration_extension_ms"] as? Int == 2_000)
        #expect(json["model_id"] as? String == "music_v2_5")
        #expect(json["source_composition_plan"] == nil)

        let seeded = DialogMusicPlanRequest(
            dialogCacheKey: "k", dialogGenerationId: generationId, prompt: "Bright",
            sourceCompositionPlan: MusicCompositionPlan(chunks: [
                .generation(MusicGenerationChunk(text: "x", durationMilliseconds: 5_000))
            ]))
        let seededJSON = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(seeded)) as? [String: Any])
        #expect(seededJSON["source_composition_plan"] != nil)
    }

    @Test("plan result decodes")
    func planResultDecoding() throws {
        let json = """
            {"model_id": "music_v2_5", "music_length_ms": 47500, "dialog_duration_ms": 44500,
             "duration_extension_ms": 3000,
             "composition_plan": {"chunks": [{"text": "a", "duration_ms": 47500}]}}
            """
        let result = try JSONDecoder().decode(DialogMusicPlanResult.self, from: Data(json.utf8))
        #expect(result.musicLengthMilliseconds == 47_500)
        #expect(result.dialogDurationMilliseconds == 44_500)
        #expect(result.compositionPlan.totalDurationMilliseconds == 47_500)
    }

    @Test("finetune list decodes the picker shape, genre optional")
    func finetuneListDecoding() throws {
        let json = """
            {"count": 2, "items": [
              {"created_by": "elevenlabs", "finetune_id": "fc7", "model_id": "music_v2",
               "name": "Gothic Power Rock", "primary_genre": "Rock", "status": "completed",
               "tags": ["Rock"], "training_progress": 1.0, "visibility": "public"},
              {"created_by": "me", "finetune_id": "abc", "model_id": "music_v2_5",
               "name": "Bird Songs", "status": "training", "tags": [],
               "training_progress": 0.4, "visibility": "private"}
            ]}
            """
        let list = try JSONDecoder().decode(MusicFinetuneList.self, from: Data(json.utf8))
        #expect(list.count == 2)
        #expect(list.items[0].primaryGenre == "Rock")
        #expect(list.items[0].isReady)
        #expect(list.items[0].model == .v2)
        #expect(list.items[1].primaryGenre == nil)
        #expect(!list.items[1].isReady)
        #expect(list.items[1].id == "abc")
    }

    @Test("generation result exposes the later show duration")
    func resultDecoding() throws {
        let json = """
            {
              "music_generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
              "mp3_url": "/api/v1/animation/dialog/music/generated/take.mp3",
              "duration_seconds": 44.25,
              "dialog_duration_ms": 39500,
              "duration_extension_ms": 5000,
              "requested_music_length_ms": 44500,
              "prompt": "A gentle instrumental outro"
            }
            """
        let result = try JSONDecoder().decode(
            DialogMusicGenerationResult.self, from: Data(json.utf8))
        #expect(result.dialogDurationMilliseconds == 39_500)
        #expect(result.requestedMusicLengthMilliseconds == 44_500)
        #expect(result.finalShowDurationSeconds == 44.25)
    }

    @Test("background music decodes from a script and remains optional")
    func backgroundMusicCompatibility() throws {
        let withMusic = """
            {
              "id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
              "title": "Scene",
              "background_music": {
                "sound_file": "dialog/music/scene.wav",
                "generation_id": "8c103a02-f6fe-4918-8a2a-f9ba7b4c49d2",
                "prompt": "Warm strings",
                "accepted_at": 1748579999000
              }
            }
            """
        let decoded = try JSONDecoder().decode(DialogScript.self, from: Data(withMusic.utf8))
        #expect(decoded.backgroundMusic?.soundFile == "dialog/music/scene.wav")

        let withoutMusic = """
            {"id":"a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2","title":"Scene"}
            """
        #expect(
            try JSONDecoder().decode(DialogScript.self, from: Data(withoutMusic.utf8))
                .backgroundMusic == nil)
    }

    @Test("upsert never sends server-managed background music")
    func upsertOmitsMusic() throws {
        let script = DialogScript(
            id: UUID(), title: "Scene", notes: "", turns: [],
            backgroundMusic: DialogBackgroundMusic(
                soundFile: "dialog/music/scene.wav", generationId: UUID(), prompt: "Warm",
                acceptedAt: 1))
        let data = try JSONEncoder().encode(UpsertDialogScriptRequest(script))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["background_music"] == nil)
    }
}
