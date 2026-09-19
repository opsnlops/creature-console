import Foundation
import Testing

@testable import Common

@Suite("Music pieces refine rather than re-roll")
struct MusicPieceTests {

    private func chunk(_ text: String, _ ms: Int64, styles: [String] = []) -> MusicGenerationChunk {
        MusicGenerationChunk(text: text, durationMilliseconds: ms, positiveStyles: styles)
    }

    private func generatedPiece() -> MusicPiece {
        MusicPiece(
            songId: "song-A", durationMilliseconds: 20_000,
            plan: MusicCompositionPlan(chunks: [
                .generation(chunk("[Intro] soft", 5_000, styles: ["strings", "warm"])),
                .generation(chunk("[Verse] builds", 10_000, styles: ["brass", "warm"])),
                .generation(chunk("[Outro] fades", 5_000, styles: ["warm"])),
            ]))
    }

    @Test("a generated take becomes a piece whose sections know where their audio is")
    func pieceFromPlan() {
        let piece = generatedPiece()
        #expect(piece.hasAudio)
        #expect(piece.sections.count == 3)
        #expect(!piece.isDirty)
        #expect(
            piece.sections[1].span
                == MusicAudioRange(
                    songId: "song-A", startMilliseconds: 5_000, endMilliseconds: 15_000))
        #expect(piece.sections[1].name == "Verse")
        #expect(piece.sections[1].directions == "builds")
        #expect(piece.globalPositiveStyles == ["warm"])
        #expect(piece.sectionStartOffsets == [0, 5_000, 15_000])
    }

    @Test("an audio-reference chunk in the used plan becomes a kept section")
    func referenceChunkBecomesKeptSection() {
        let piece = MusicPiece(
            songId: "song-B", durationMilliseconds: 9_000,
            plan: MusicCompositionPlan(chunks: [
                .audioReference(
                    MusicAudioRange(songId: "song-A", startMilliseconds: 0, endMilliseconds: 4_000)),
                .generation(chunk("[Rest]", 5_000)),
            ]))
        #expect(piece.sections[0].name == "Kept from an earlier take")
        #expect(piece.sections[0].span?.songId == "song-B")
        #expect(!piece.sections[0].isDirty)
    }

    @Test("a clean piece refines to nothing but references")
    func cleanPieceReferencesEverything() {
        let plan = generatedPiece().refinementPlan()
        #expect(plan.chunks.allSatisfy { $0.isAudioReference })
        #expect(plan.totalDurationMilliseconds == 20_000)
    }

    @Test("editing one section regenerates only that section, conditioned on the song")
    func editOneSection() {
        var piece = generatedPiece()
        piece.sections[1].content.positiveStyles.append("pizzicato")
        #expect(piece.dirtySections.map(\.name) == ["Verse"])

        let plan = piece.refinementPlan(conditionStrength: .high)
        #expect(plan.chunks[0] == .audioReference(piece.sections[0].span!))
        #expect(plan.chunks[2] == .audioReference(piece.sections[2].span!))
        guard case .generation(let verse) = plan.chunks[1] else {
            Issue.record("expected the verse to be composed")
            return
        }
        #expect(verse.positiveStyles == ["brass", "warm", "pizzicato"])
        #expect(
            verse.conditioningReference
                == MusicAudioRange(songId: "song-A", startMilliseconds: 0, endMilliseconds: 20_000))
        #expect(verse.conditionStrength == .high)
        #expect(plan.validationProblems(dialogDurationMilliseconds: nil).isEmpty)
    }

    @Test("a section's own conditioning reference is respected")
    func keepsExplicitConditioning() {
        var piece = generatedPiece()
        let other = MusicAudioRange(songId: "song-Z", startMilliseconds: 0, endMilliseconds: 3_000)
        piece.sections[0].content.conditioningReference = other
        piece.sections[0].content.conditionStrength = .low
        guard case .generation(let intro) = piece.refinementPlan().chunks[0] else {
            Issue.record("expected the intro to be composed")
            return
        }
        #expect(intro.conditioningReference == other)
        #expect(intro.conditionStrength == .low)
    }

    @Test("changing a section's length makes it dirty")
    func lengthChangeIsDirty() {
        var piece = generatedPiece()
        piece.sections[2].content.durationMilliseconds = 8_000
        #expect(piece.sections[2].isDirty)
        #expect(piece.plannedDurationMilliseconds == 23_000)
    }

    @Test("a blank piece composes everything with no conditioning")
    func blankPiece() {
        let piece = MusicPiece.blank(sections: [chunk("[Intro]", 5_000), chunk("[Outro]", 5_000)])
        #expect(!piece.hasAudio)
        #expect(piece.isDirty)
        let plan = piece.refinementPlan()
        #expect(plan.chunks.allSatisfy { !$0.isAudioReference })
        guard case .generation(let intro) = plan.chunks[0] else { return }
        #expect(intro.conditioningReference == nil)
    }

    @Test("committing after a refinement moves every section onto the new song")
    func committed() {
        var piece = generatedPiece()
        piece.insertSection(chunk("[Bridge]", 4_000), at: 2)
        #expect(piece.sections[2].span == nil)
        let next = piece.committed(songId: "song-C", durationMilliseconds: 24_000)
        #expect(!next.isDirty)
        #expect(next.songId == "song-C")
        #expect(next.sections.map { $0.span?.startMilliseconds } == [0, 5_000, 15_000, 19_000])
        #expect(next.sections[2].span?.songId == "song-C")
        #expect(next.sections[2].committedContent == next.sections[2].content)
    }

    @Test("reverting drops edits and unbaked sections")
    func reverted() {
        var piece = generatedPiece()
        piece.sections[0].content.text = "[Intro] louder"
        piece.insertSection(chunk("[New]", 3_000), at: 3)
        let restored = piece.reverted()
        let pristine = generatedPiece()
        #expect(restored.songId == pristine.songId)
        #expect(restored.sections.map(\.content) == pristine.sections.map(\.content))
        #expect(restored.sections.map(\.span) == pristine.sections.map(\.span))
        #expect(!restored.isDirty)
    }

    @Test("splitting a clean section keeps both halves' audio")
    func splitCleanSection() {
        var piece = generatedPiece()
        let verse = piece.sections[1].id
        piece.splitSection(id: verse, at: 4_000)
        #expect(piece.sections.count == 4)
        #expect(piece.sections[1].content.durationMilliseconds == 4_000)
        #expect(piece.sections[2].content.durationMilliseconds == 6_000)
        #expect(
            piece.sections[1].span
                == MusicAudioRange(
                    songId: "song-A", startMilliseconds: 5_000, endMilliseconds: 9_000))
        #expect(
            piece.sections[2].span
                == MusicAudioRange(
                    songId: "song-A", startMilliseconds: 9_000, endMilliseconds: 15_000))
        #expect(!piece.isDirty)
        // Too close to an edge: nothing happens.
        let before = piece
        piece.splitSection(id: piece.sections[0].id, at: 1_000)
        #expect(piece == before)
    }

    @Test("splitting a dirty section leaves both halves to be composed")
    func splitDirtySection() {
        var piece = generatedPiece()
        piece.sections[1].content.text = "[Verse] changed"
        piece.splitSection(id: piece.sections[1].id, at: 5_000)
        #expect(piece.sections[1].isDirty)
        #expect(piece.sections[2].isDirty)
        #expect(piece.sections[2].span == nil)
    }

    @Test("global styles are the ones every section shares and can be added or removed")
    func globalStyles() {
        var piece = generatedPiece()
        piece.addGlobalStyle("128 BPM")
        #expect(piece.globalPositiveStyles == ["warm", "128 BPM"])
        #expect(piece.sections.allSatisfy { $0.content.positiveStyles.contains("128 BPM") })
        piece.removeGlobalStyle("warm")
        #expect(piece.globalPositiveStyles == ["128 BPM"])
        #expect(piece.sections[0].content.positiveStyles == ["strings", "128 BPM"])
        piece.addGlobalStyle("drums", negative: true)
        #expect(piece.globalNegativeStyles == ["drums"])
    }

    @Test("section names round-trip through the [Name] prefix")
    func names() {
        var section = MusicSection(content: chunk("no name here", 3_000))
        #expect(section.name == "")
        #expect(section.directions == "no name here")
        section.setName("Chorus", directions: "big and bright")
        #expect(section.content.text == "[Chorus] big and bright")
        section.setName("Chorus", directions: "")
        #expect(section.content.text == "[Chorus]")
        section.setName("", directions: "just words")
        #expect(section.content.text == "just words")
        #expect(
            MusicSection.splitName("[Reveal] {triumphant swell}") == (
                "Reveal", "{triumphant swell}"
            ))
    }

    @Test("instrumental keeps the header and directions and drops lyric lines")
    func instrumental() {
        let sung = MusicGenerationChunk(
            text: "[Jingle] {bright}\nPretty bird, fly so high!\n(chirp chirp chirp)\n{slower}",
            durationMilliseconds: 8_000)
        #expect(sung.instrumental().text == "[Jingle] {bright}\n{slower}")
        let headed = MusicGenerationChunk(
            text: "[Jingle]\nPretty bird!", durationMilliseconds: 8_000)
        #expect(headed.instrumental().text == "[Jingle]")
        let plain = MusicGenerationChunk(text: "[Intro] soft", durationMilliseconds: 8_000)
        #expect(plain.instrumental().text == "[Intro] soft")
    }

    @Test("moving and removing sections")
    func moveAndRemove() {
        var piece = generatedPiece()
        let outro = piece.sections[2].id
        piece.moveSection(id: outro, by: -1)
        #expect(piece.sections.map(\.name) == ["Intro", "Outro", "Verse"])
        piece.moveSection(id: outro, by: -5)
        #expect(piece.sections.map(\.name) == ["Intro", "Outro", "Verse"])
        piece.removeSection(id: outro)
        #expect(piece.sections.map(\.name) == ["Intro", "Verse"])
    }
}
