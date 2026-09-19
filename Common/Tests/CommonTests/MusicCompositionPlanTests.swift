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

    @Test("keeping the opening references the kept span and trims the straddling section")
    func keepingOpening() throws {
        let plan = MusicCompositionPlan(chunks: [
            generation("Intro", 4_000, styles: ["strings"]),
            generation("Verse", 10_000, styles: ["brass"]),
            generation("Outro", 6_000),
        ])
        let kept = try #require(plan.keepingOpening(upTo: 9_000, of: "song-7"))
        #expect(kept.totalDurationMilliseconds == plan.totalDurationMilliseconds)
        #expect(kept.chunks.count == 3)
        guard case .audioReference(let range) = kept.chunks[0] else {
            Issue.record("expected an audio reference first")
            return
        }
        #expect(
            range == MusicAudioRange(songId: "song-7", startMilliseconds: 0, endMilliseconds: 9_000)
        )
        guard case .generation(let tail) = kept.chunks[1] else {
            Issue.record("expected the trimmed verse second")
            return
        }
        #expect(tail.text == "Verse")
        #expect(tail.positiveStyles == ["brass"])
        #expect(tail.durationMilliseconds == 5_000)
        #expect(kept.chunks[2] == plan.chunks[2])
    }

    @Test("keeping the opening on a section boundary drops nothing and splits nothing")
    func keepingOpeningOnBoundary() throws {
        let plan = MusicCompositionPlan(chunks: [generation("A", 4_000), generation("B", 4_000)])
        let kept = try #require(plan.keepingOpening(upTo: 4_000, of: "s"))
        #expect(kept.chunks.count == 2)
        #expect(kept.chunks[0].isAudioReference)
        #expect(kept.chunks[1] == plan.chunks[1])
    }

    @Test("keeping the opening refuses keep points that leave a too-short piece")
    func keepingOpeningLimits() {
        let plan = MusicCompositionPlan(chunks: [generation("A", 4_000), generation("B", 4_000)])
        #expect(plan.keepingOpening(upTo: 2_000, of: "s") == nil)  // reference too short
        #expect(plan.keepingOpening(upTo: 6_000, of: "s") == nil)  // tail of B too short
        #expect(plan.keepingOpening(upTo: 8_000, of: "s") == nil)  // nothing left to make
    }

    @Test("a long kept span is split into legal reference pieces")
    func keepingOpeningSplitsLongSpans() throws {
        let plan = MusicCompositionPlan(chunks: [
            generation("A", 120_000), generation("B", 120_000), generation("C", 20_000),
        ])
        let kept = try #require(plan.keepingOpening(upTo: 240_000, of: "s"))
        let references = kept.chunks.filter(\.isAudioReference)
        #expect(references.count == 2)
        #expect(references.allSatisfy { $0.durationMilliseconds == 120_000 })
        #expect(kept.totalDurationMilliseconds == 260_000)
        #expect(kept.validationProblems(dialogDurationMilliseconds: nil).isEmpty)
    }

    @Test("keeping the opening trims a referenced span from a prior take")
    func keepingOpeningTrimsReferences() throws {
        let plan = MusicCompositionPlan(chunks: [
            .audioReference(
                MusicAudioRange(songId: "old", startMilliseconds: 2_000, endMilliseconds: 12_000)),
            generation("B", 5_000),
        ])
        let kept = try #require(plan.keepingOpening(upTo: 4_000, of: "new"))
        #expect(kept.chunks.count == 3)
        guard case .audioReference(let trimmed) = kept.chunks[1] else {
            Issue.record("expected the old reference, trimmed")
            return
        }
        #expect(
            trimmed
                == MusicAudioRange(songId: "old", startMilliseconds: 6_000, endMilliseconds: 12_000)
        )
    }

    @Test("conditioning applies to generation sections only and can be cleared")
    func conditioning() {
        let plan = MusicCompositionPlan(chunks: [
            .audioReference(
                MusicAudioRange(songId: "s", startMilliseconds: 0, endMilliseconds: 4_000)),
            generation("B", 5_000),
        ])
        let reference = MusicAudioRange.referenceSpan(of: "s", durationMilliseconds: 500_000)
        #expect(reference.endMilliseconds == 120_000)
        let conditioned = plan.conditioned(on: reference, strength: .medium)
        #expect(conditioned.chunks[0] == plan.chunks[0])
        guard case .generation(let chunk) = conditioned.chunks[1] else {
            Issue.record("expected a generation chunk")
            return
        }
        #expect(chunk.conditioningReference == reference)
        #expect(chunk.conditionStrength == .medium)
        #expect(conditioned.unconditioned() == plan)
    }

    @Test("chunk start offsets accumulate")
    func offsets() {
        let plan = MusicCompositionPlan(chunks: [generation("A", 4_000), generation("B", 6_000)])
        #expect(plan.chunkStartOffsets == [0, 4_000])
    }
}
