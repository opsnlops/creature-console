import Foundation
import Testing

@testable import Common

@Suite("Dialog preview DTO decoding")
struct DialogPreviewDTOTests {

    @Test("decodes preview/meta response")
    func decodesMeta() throws {
        let json = """
            {
              "cache_key": "6bbb1ff65cbb8f33",
              "generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
              "cached": false,
              "audio_url": "/api/v1/animation/dialog/preview/audio/6bbb1ff6/a9262b22.wav",
              "audio_format": "pcm_48000",
              "sample_rate": 48000,
              "duration_seconds": 24.56,
              "voice_segments": [
                { "voice_id": "v1", "character_start_index": 0, "character_end_index": 28, "dialog_input_index": 0 }
              ],
              "forced_alignment_words": [ { "text": "Beaky", "start": 0.12, "end": 0.48 } ],
              "forced_alignment_chars": [ { "text": "B", "start": 0.12, "end": 0.20 } ],
              "forced_alignment_loss": 0.07
            }
            """
        let dto = try JSONDecoder().decode(DialogPreviewMetaDTO.self, from: Data(json.utf8))
        #expect(dto.cacheKey == "6bbb1ff65cbb8f33")
        #expect(dto.generationId == UUID(uuidString: "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2"))
        #expect(dto.cached == false)
        #expect(dto.audioUrl.hasPrefix("/api/v1/animation/dialog/preview/audio/"))
        #expect(dto.sampleRate == 48000)
        #expect(dto.durationSeconds == 24.56)
        #expect(dto.voiceSegments.first?.dialogInputIndex == 0)
        #expect(dto.forcedAlignmentWords.first?.text == "Beaky")
        #expect(dto.forcedAlignmentChars.first?.start == 0.12)
        #expect(dto.forcedAlignmentLoss == 0.07)
    }

    @Test("decodes preview/meta with only the scalar fields")
    func decodesMinimalMeta() throws {
        let json = """
            {
              "cache_key": "abc",
              "generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
              "audio_url": "/api/v1/x.wav"
            }
            """
        let dto = try JSONDecoder().decode(DialogPreviewMetaDTO.self, from: Data(json.utf8))
        #expect(dto.cached == false)
        #expect(dto.voiceSegments.isEmpty)
        #expect(dto.forcedAlignmentWords.isEmpty)
        #expect(dto.forcedAlignmentLoss == nil)
    }

    @Test("decodes preview/lookup response with generations")
    func decodesLookup() throws {
        let json = """
            {
              "cache_key": "6bbb1ff6",
              "latest_generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
              "generations": [
                { "generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2", "created_at": "2026-05-29T07:01:23Z" },
                { "generation_id": "8c103a02-f6fe-4918-8a2a-f9ba7b4c49d2", "created_at": "2026-05-29T06:58:11Z" }
              ]
            }
            """
        let dto = try JSONDecoder().decode(DialogPreviewLookupDTO.self, from: Data(json.utf8))
        #expect(dto.cacheKey == "6bbb1ff6")
        #expect(dto.latestGenerationId == UUID(uuidString: "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2"))
        #expect(dto.generations.count == 2)
        #expect(dto.generations.first?.createdAtDate != nil)
    }

    @Test("preview request always encodes turns, with a lowercased generation id")
    func encodesPreviewRequest() throws {
        let gen = UUID()
        let request = DialogPreviewRequest.fromTurns(
            [DialogScriptTurn(creatureId: "abc", text: "hi")], generationId: gen, regenerate: true)
        let data = try JSONEncoder().encode(request)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Preview is turns-only on the wire — there is no script_id.
        #expect(obj["script_id"] == nil)
        #expect((obj["turns"] as? [[String: Any]])?.count == 1)
        #expect(obj["generation_id"] as? String == gen.uuidString.lowercased())
        #expect(obj["regenerate"] as? Bool == true)
    }
}
