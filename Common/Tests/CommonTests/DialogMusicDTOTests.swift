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
