import Foundation

/// How an editable piece meets the library (server #202): a saved version becomes the piece
/// being edited, and the piece's edits become a sections-mode generation the server turns into
/// the refinement plan.
extension MusicPiece {

    /// A saved version as the piece being edited: its sections, each committed to its span in
    /// the version's song.
    public init(version: SavedMusicVersion) {
        var sections: [MusicSection] = []
        var offset: Int64 = 0
        for content in version.sections {
            let length = content.durationMilliseconds
            let span = MusicAudioRange(
                songId: version.songId, startMilliseconds: offset, endMilliseconds: offset + length)
            sections.append(
                MusicSection(
                    content: content.unconditioned(), committedContent: content.unconditioned(),
                    span: version.canBeReferenced ? span : nil))
            offset += length
        }
        self.init(
            songId: version.songId, durationMilliseconds: version.durationMilliseconds,
            sections: sections)
    }

    /// The sections as the server's refinement builder wants them: content only, no
    /// conditioning (the server adds that for changed sections).
    public var serverSections: [MusicGenerationChunk] {
        sections.map { $0.content.unconditioned() }
    }

    /// Indices the server may keep from `base`: sections that are clean *and* sit at the same
    /// index with the same content as the base version's section there. A clean section that
    /// moved can't be kept by index (the server matches by position), so it is composed again,
    /// conditioned on the old audio.
    public func keptIndices(against base: [MusicGenerationChunk]) -> [Int] {
        sections.enumerated().compactMap { index, section in
            guard !section.isDirty, base.indices.contains(index),
                base[index].unconditioned() == section.content.unconditioned()
            else { return nil }
            return index
        }
    }

    /// The piece after the server saved a refinement as `version`: the same sections, committed
    /// to the new song. Falls back to the version's own sections if the counts disagree (the
    /// server is the record).
    public func committed(version: SavedMusicVersion) -> MusicPiece {
        guard version.sections.count == sections.count else {
            return MusicPiece(version: version)
        }
        return committed(
            songId: version.songId, durationMilliseconds: version.durationMilliseconds)
    }

    /// The server's proposal from the instruction box, laid over this piece: proposed
    /// sections replace the current ones, keeping ids where the index exists so selection and
    /// dirty state read naturally — a section whose proposed content differs is dirty by
    /// construction, one that matches stays clean.
    public func applying(proposal: [MusicGenerationChunk]) -> MusicPiece {
        var updated = self
        var result: [MusicSection] = []
        for (index, content) in proposal.enumerated() {
            if sections.indices.contains(index) {
                var section = sections[index]
                section.content = content.unconditioned()
                result.append(section)
            } else {
                result.append(MusicSection(content: content.unconditioned()))
            }
        }
        updated.sections = result
        return updated
    }
}
