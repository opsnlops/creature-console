import Foundation

/// One section of a piece as the author sees it: what it should sound like, and where its
/// audio currently lives. Editing the content makes the section dirty; the next refinement
/// regenerates dirty sections and references the rest by their span in the current song.
public struct MusicSection: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    /// The section as it is being edited.
    public var content: MusicGenerationChunk
    /// The section as it was when the current audio was made. Nil for a section added since.
    public var committedContent: MusicGenerationChunk?
    /// Where this section's audio lives in the current song. Nil for a section added since,
    /// or when the piece has no audio yet.
    public var span: MusicAudioRange?

    public init(
        id: UUID = UUID(), content: MusicGenerationChunk,
        committedContent: MusicGenerationChunk? = nil, span: MusicAudioRange? = nil
    ) {
        self.id = id
        self.content = content
        self.committedContent = committedContent
        self.span = span
    }

    /// Whether the audio on file still matches the content. A section with no audio is dirty
    /// by definition.
    public var isDirty: Bool {
        guard let committedContent, let span else { return true }
        return committedContent != content
            || span.lengthMilliseconds != content.durationMilliseconds
    }

    /// The section's name, from the `[Name]` prefix ElevenLabs and the planner both use.
    public var name: String {
        MusicSection.splitName(content.text).name
    }

    /// The directions after the `[Name]` prefix.
    public var directions: String {
        MusicSection.splitName(content.text).directions
    }

    /// Rewrites the text as `[name] directions`, dropping an empty name or directions.
    public mutating func setName(_ name: String, directions: String) {
        content.text = MusicSection.joinName(name, directions: directions)
    }

    public static func splitName(_ text: String) -> (name: String, directions: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") else {
            return ("", trimmed)
        }
        let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            .trimmingCharacters(in: .whitespaces)
        let rest = String(trimmed[trimmed.index(after: close)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, rest)
    }

    public static func joinName(_ name: String, directions: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        let directions = directions.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (name.isEmpty, directions.isEmpty) {
        case (true, _): return directions
        case (false, true): return "[\(name)]"
        case (false, false): return "[\(name)] \(directions)"
        }
    }
}

/// A piece of music as something to refine rather than re-roll: the song ElevenLabs holds
/// for it, and the sections it is made of. A refinement plan references every section whose
/// audio still matches its content and composes only the ones that changed, conditioned on the
/// current song so the new parts belong with the old.
public struct MusicPiece: Equatable, Hashable, Sendable {
    /// ElevenLabs' id for the current audio; empty until something has been generated.
    public var songId: String
    public var durationMilliseconds: Int64
    public var sections: [MusicSection]
    /// The layout the current audio was made from: the sections, in order, as committed. A
    /// removed or reordered section leaves every survivor clean, so the piece compares its
    /// order against this to know it changed — and `reverted()` restores it from here.
    public private(set) var committedSections: [MusicSection]

    public init(songId: String, durationMilliseconds: Int64, sections: [MusicSection]) {
        self.songId = songId
        self.durationMilliseconds = durationMilliseconds
        self.sections = sections
        self.committedSections = sections.filter { !$0.isDirty }
    }

    /// An empty piece with nothing generated yet.
    public static func blank(sections: [MusicGenerationChunk] = []) -> MusicPiece {
        MusicPiece(
            songId: "", durationMilliseconds: 0,
            sections: sections.map { MusicSection(content: $0) })
    }

    /// The piece a generated take *is*: every chunk of the plan the server used becomes a
    /// section whose audio lives at that chunk's offset in the take's song. A chunk that was
    /// itself an audio reference has no content of its own on the server; it is described as
    /// kept from an earlier take so the author can still name it or rewrite it.
    public init(songId: String, durationMilliseconds: Int64, plan: MusicCompositionPlan) {
        var sections: [MusicSection] = []
        var offset: Int64 = 0
        for chunk in plan.chunks {
            let length = chunk.durationMilliseconds
            let span = MusicAudioRange(
                songId: songId, startMilliseconds: offset, endMilliseconds: offset + length)
            let content: MusicGenerationChunk
            switch chunk {
            case .generation(let generation):
                content = generation.unconditioned()
            case .audioReference:
                content = MusicGenerationChunk(
                    text: "[Kept from an earlier take]", durationMilliseconds: length)
            }
            sections.append(MusicSection(content: content, committedContent: content, span: span))
            offset += length
        }
        self.init(songId: songId, durationMilliseconds: durationMilliseconds, sections: sections)
    }

    public var hasAudio: Bool { !songId.isEmpty && durationMilliseconds > 0 }

    public var plannedDurationMilliseconds: Int64 {
        sections.reduce(0) { $0 + $1.content.durationMilliseconds }
    }

    public var dirtySections: [MusicSection] { sections.filter(\.isDirty) }

    /// Whether sections were removed, added or reordered since the audio was made: the
    /// sections' spans no longer tile the current song from start to end, in order. A split
    /// keeps tiling it (two halves of one span) and so is not a change by itself.
    public var hasLayoutChanges: Bool {
        guard hasAudio else { return false }
        var cursor: Int64 = 0
        for section in sections {
            guard let span = section.span, span.songId == songId,
                span.startMilliseconds == cursor
            else { return true }
            cursor = span.endMilliseconds
        }
        return cursor != durationMilliseconds
    }

    /// Whether the audio on file no longer describes the piece: a section changed, or the
    /// layout did.
    public var isDirty: Bool { hasLayoutChanges || sections.contains(where: \.isDirty) }

    /// Start offset of each section in the *planned* piece, in order.
    public var sectionStartOffsets: [Int64] {
        var offsets: [Int64] = []
        var cursor: Int64 = 0
        for section in sections {
            offsets.append(cursor)
            cursor += section.content.durationMilliseconds
        }
        return offsets
    }

    /// The span of the current song a changed section should sound like: the whole song, capped
    /// at the longest span one chunk may reference.
    public var conditioningSpan: MusicAudioRange? {
        guard hasAudio else { return nil }
        return MusicAudioRange.referenceSpan(of: songId, durationMilliseconds: durationMilliseconds)
    }

    /// The minimal plan that turns the edits into audio. Clean sections become audio references
    /// to their span in the current song; dirty ones are composed, each conditioned on the
    /// current song at `strength` (when the piece has audio and the section doesn't already
    /// carry its own reference). A piece without audio is composed entirely from its content.
    public func refinementPlan(conditionStrength strength: MusicConditionStrength = .high)
        -> MusicCompositionPlan
    {
        let conditioning = conditioningSpan
        return MusicCompositionPlan(
            chunks: sections.map { section in
                if !section.isDirty, let span = section.span {
                    return .audioReference(span)
                }
                var content = section.content
                if content.conditioningReference == nil, let conditioning {
                    content.conditioningReference = conditioning
                    content.conditionStrength = strength
                }
                return .generation(content)
            })
    }

    /// The piece after a refinement succeeded: the same sections, now committed, with their
    /// audio at their offsets in the new song.
    public func committed(songId newSongId: String, durationMilliseconds newDuration: Int64)
        -> MusicPiece
    {
        var offset: Int64 = 0
        let committedSections = sections.map { section -> MusicSection in
            let length = section.content.durationMilliseconds
            var updated = section
            updated.committedContent = section.content
            updated.span = MusicAudioRange(
                songId: newSongId, startMilliseconds: offset, endMilliseconds: offset + length)
            offset += length
            return updated
        }
        return MusicPiece(
            songId: newSongId, durationMilliseconds: newDuration, sections: committedSections)
    }

    /// Discards edits: the committed layout comes back, removed sections and all, with every
    /// section's content as its audio was made from. Sections added since are dropped.
    public func reverted() -> MusicPiece {
        var piece = self
        piece.sections = committedSections.map { section in
            var restored = section
            if let committed = section.committedContent {
                restored.content = committed
            }
            return restored
        }
        return piece
    }

    // MARK: Editing

    public mutating func insertSection(_ content: MusicGenerationChunk, at index: Int) {
        sections.insert(MusicSection(content: content), at: min(max(index, 0), sections.count))
    }

    public mutating func removeSection(id: MusicSection.ID) {
        sections.removeAll { $0.id == id }
    }

    public mutating func moveSection(id: MusicSection.ID, by delta: Int) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard sections.indices.contains(target) else { return }
        sections.swapAt(index, target)
    }

    /// Splits a section in two at `milliseconds` from its start. The head keeps its audio when
    /// the section was clean (a reference can be trimmed); the tail is new and must be composed.
    public mutating func splitSection(id: MusicSection.ID, at milliseconds: Int64) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        let section = sections[index]
        let total = section.content.durationMilliseconds
        let minimum = DialogLimits.minMusicChunkMilliseconds
        guard milliseconds >= minimum, total - milliseconds >= minimum else { return }
        var head = section
        head.content.durationMilliseconds = milliseconds
        if let span = section.span, !section.isDirty {
            head.span = MusicAudioRange(
                songId: span.songId, startMilliseconds: span.startMilliseconds,
                endMilliseconds: span.startMilliseconds + milliseconds)
            head.committedContent = head.content
        }
        var tailContent = section.content
        tailContent.durationMilliseconds = total - milliseconds
        var tail = MusicSection(content: tailContent)
        if let span = section.span, !section.isDirty {
            // The tail's audio exists too: it is the rest of the original span.
            tail = MusicSection(
                content: tailContent, committedContent: tailContent,
                span: MusicAudioRange(
                    songId: span.songId, startMilliseconds: span.startMilliseconds + milliseconds,
                    endMilliseconds: span.endMilliseconds))
        }
        sections.replaceSubrange(index...index, with: [head, tail])
    }

    /// Every section shares the given styles: added to each section's list, once.
    public var globalPositiveStyles: [String] { sharedStyles(\.positiveStyles) }
    public var globalNegativeStyles: [String] { sharedStyles(\.negativeStyles) }

    public mutating func addGlobalStyle(_ style: String, negative: Bool = false) {
        for index in sections.indices {
            let keyPath: WritableKeyPath<MusicGenerationChunk, [String]> =
                negative ? \.negativeStyles : \.positiveStyles
            if !sections[index].content[keyPath: keyPath].contains(style),
                sections[index].content[keyPath: keyPath].count < DialogLimits.maxMusicStyles
            {
                sections[index].content[keyPath: keyPath].append(style)
            }
        }
    }

    public mutating func removeGlobalStyle(_ style: String, negative: Bool = false) {
        for index in sections.indices {
            if negative {
                sections[index].content.negativeStyles.removeAll { $0 == style }
            } else {
                sections[index].content.positiveStyles.removeAll { $0 == style }
            }
        }
    }

    private func sharedStyles(_ keyPath: KeyPath<MusicGenerationChunk, [String]>) -> [String] {
        guard let first = sections.first else { return [] }
        return first.content[keyPath: keyPath].filter { style in
            sections.allSatisfy { $0.content[keyPath: keyPath].contains(style) }
        }
    }
}

extension MusicGenerationChunk {
    /// The same chunk with no conditioning reference.
    public func unconditioned() -> MusicGenerationChunk {
        var chunk = self
        chunk.conditioningReference = nil
        chunk.conditionStrength = nil
        return chunk
    }

    /// The same chunk without lyric lines. In plan and sections modes "instrumental" is nothing
    /// more than leaving lyrics out of the text — the planner writes them if you let it — so this
    /// keeps the `[Section]` header and any `{direction}` lines and drops the rest.
    public func instrumental() -> MusicGenerationChunk {
        var chunk = self
        let kept = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                (line.hasPrefix("[") && line.contains("]"))
                    || (line.hasPrefix("{") && line.hasSuffix("}"))
            }
        chunk.text = kept.joined(separator: "\n")
        return chunk
    }
}
