import Foundation
import Testing

@testable import Common

@Suite("Music composition plans")
struct MusicCompositionPlanTests {

    private func generation(_ text: String, _ ms: Int64, styles: [String] = [])
        -> MusicPlanChunk
    {
        .generation(
            MusicGenerationChunk(text: text, durationMilliseconds: ms, positiveStyles: styles))
    }

    @Test("chunks decode by shape and encode without null conditioning keys")
    func chunkCodingRoundTrip() throws {
        let json = """
            {"chunks": [
              {"song_id": "song-1", "range": {"start_ms": 0, "end_ms": 4000}},
              {"text": "[Intro] {soft}", "duration_ms": 5000,
               "positive_styles": ["strings"], "negative_styles": [],
               "context_adherence": "medium",
               "conditioning_ref": null, "condition_strength": null}
            ]}
            """
        let plan = try JSONDecoder().decode(MusicCompositionPlan.self, from: Data(json.utf8))
        #expect(plan.chunks.count == 2)
        #expect(plan.totalDurationMilliseconds == 9_000)
        guard case .audioReference(let range) = plan.chunks[0] else {
            Issue.record("first chunk should be an audio reference")
            return
        }
        #expect(range.songId == "song-1")
        #expect(range.lengthMilliseconds == 4_000)
        guard case .generation(let chunk) = plan.chunks[1] else {
            Issue.record("second chunk should be a generation chunk")
            return
        }
        #expect(chunk.contextAdherence == .medium)
        #expect(chunk.conditioningReference == nil)
        #expect(chunk.conditionStrength == nil)

        let encoded = try JSONEncoder().encode(plan)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let chunks = try #require(object["chunks"] as? [[String: Any]])
        #expect(chunks[0]["song_id"] as? String == "song-1")
        #expect((chunks[0]["range"] as? [String: Any])?["end_ms"] as? Int == 4_000)
        #expect(chunks[1]["conditioning_ref"] == nil)
        #expect(chunks[1]["condition_strength"] == nil)
        #expect(chunks[1]["context_adherence"] as? String == "medium")

        let reparsed = try JSONDecoder().decode(MusicCompositionPlan.self, from: encoded)
        #expect(reparsed == plan)
    }

    @Test("a chunk with both song_id and text is rejected")
    func rejectsAmbiguousChunk() {
        let json = """
            {"chunks": [{"song_id": "x", "range": {"start_ms": 0, "end_ms": 4000}, "text": "hi"}]}
            """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MusicCompositionPlan.self, from: Data(json.utf8))
        }
    }

    @Test("conditioning references round-trip when set")
    func conditioningRoundTrip() throws {
        let reference = MusicAudioRange(
            songId: "song-2", startMilliseconds: 0, endMilliseconds: 8_000)
        let plan = MusicCompositionPlan(chunks: [
            .generation(
                MusicGenerationChunk(
                    text: "Verse", durationMilliseconds: 6_000,
                    conditioningReference: reference, conditionStrength: .xhigh))
        ])
        let data = try JSONEncoder().encode(plan)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let chunk = try #require((object["chunks"] as? [[String: Any]])?.first)
        #expect((chunk["conditioning_ref"] as? [String: Any])?["song_id"] as? String == "song-2")
        #expect(chunk["condition_strength"] as? String == "xhigh")
        #expect(try JSONDecoder().decode(MusicCompositionPlan.self, from: data) == plan)
    }

    @Test("validation mirrors the server's limits")
    func validation() {
        let good = MusicCompositionPlan(chunks: [
            generation("Intro", 5_000), generation("Outro", 5_000),
        ])
        #expect(good.validationProblems(dialogDurationMilliseconds: 9_000).isEmpty)

        #expect(
            MusicCompositionPlan(chunks: []).validationProblems(dialogDurationMilliseconds: nil)
                == ["A plan needs at least one section."])

        let short = MusicCompositionPlan(chunks: [generation("Blip", 2_000)])
        #expect(
            short.validationProblems(dialogDurationMilliseconds: nil).contains {
                $0.hasPrefix("Section 1 must last between 3 s and 120 s")
            })

        let uncovered = good.validationProblems(dialogDurationMilliseconds: 12_000)
        #expect(uncovered.count == 1)
        #expect(uncovered[0].contains("music must cover the speech"))

        let blank = MusicCompositionPlan(chunks: [generation("   ", 5_000)])
        #expect(
            blank.validationProblems(dialogDurationMilliseconds: nil) == [
                "Section 1 needs a description."
            ])

        let strengthWithoutRef = MusicCompositionPlan(chunks: [
            .generation(
                MusicGenerationChunk(
                    text: "x", durationMilliseconds: 5_000, conditionStrength: .low))
        ])
        #expect(
            strengthWithoutRef.validationProblems(dialogDurationMilliseconds: nil)
                == ["Section 1 sets a condition strength without a reference take."])

        let tooMany = MusicCompositionPlan(
            chunks: Array(repeating: generation("x", 20_000), count: 31))
        let problems = tooMany.validationProblems(dialogDurationMilliseconds: nil)
        #expect(problems.contains("A plan can have at most 30 sections."))
        #expect(problems.contains { $0.contains("the most the server allows is 600 s") })
    }

    @Test("a reference span is the whole take capped at one section's maximum")
    func referenceSpan() {
        let reference = MusicAudioRange.referenceSpan(of: "s", durationMilliseconds: 500_000)
        #expect(reference.endMilliseconds == 120_000)
        #expect(
            MusicAudioRange.referenceSpan(of: "s", durationMilliseconds: 9_000).endMilliseconds
                == 9_000)
    }

    @Test("chunk start offsets accumulate")
    func offsets() {
        let plan = MusicCompositionPlan(chunks: [generation("A", 4_000), generation("B", 6_000)])
        #expect(plan.chunkStartOffsets == [0, 4_000])
    }
}
