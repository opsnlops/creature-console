import Foundation

/// This is a local version of the `AnimationMetadata` that's sent over the wire
///
/// The server's codec (creature-server `AnimationMetadata.cpp`, 3.45.0+) **rejects unknown
/// keys** and omits every optional it has no value for, so this type is hand-Codable rather
/// than synthesized: it must send exactly the server's field set, and it must decode a
/// payload where any optional key is simply missing.
///
/// **IMPORTANT**: This DTO must stay in sync with `AnimationMetadataModel` in the GUI package.
/// Any changes to fields here must be reflected in AnimationMetadataModel.swift and vice versa.
public struct AnimationMetadata: Hashable, Equatable, Codable, Identifiable, Sendable {

    public var id: AnimationIdentifier
    public var title: String
    public var millisecondsPerFrame: UInt32 = 20
    /// Free-text note. The server omits this when it's empty, and so do we — an empty note
    /// and no note are the same thing.
    public var note: String
    public var soundFile: String
    public var numberOfFrames: UInt32
    public var multitrackAudio: Bool = false

    /// Provenance for animations rendered from a dialog. `sourceScriptId` is a *soft* pointer
    /// (the script may have been deleted — treat 404 on lookup as expected). `sourceScriptTurns`
    /// is the authoritative copy-on-write snapshot of what was rendered. Both are absent for
    /// animations not rendered from dialog. See the multichar-dialog feature.
    public var sourceScriptId: String?
    public var sourceScriptTurns: [DialogScriptTurn]?
    /// The stage this animation was rendered against (issue #119), if any. Soft pointer like
    /// `sourceScriptId` — the stage may have been deleted; the render still plays.
    ///
    /// The server requires this and ``sourceStageUpdatedAt`` to be present or absent together,
    /// so ``encode(to:)`` only writes the pair.
    public var sourceStageId: String?
    /// The stage's `updated_at` at the moment of render, epoch milliseconds. Comparing this to
    /// the stage's *current* `updated_at` is the staleness test — strictly older means the stage
    /// has moved since this was rendered.
    public var sourceStageUpdatedAt: Int64?
    /// Where every creature stood at render time. A copy-on-write snapshot, like
    /// ``sourceScriptTurns``: the stage document can move afterwards without changing what this
    /// render meant. Console-owned keys inside each placement round-trip verbatim.
    public var sourceStagePlacements: [StagePlacement]?
    /// The RNG seed the renderer used. With ``sourceRenderChoices`` this is what makes a render
    /// reproducible.
    public var renderSeed: UInt64?
    /// Which speech and idle loops the renderer picked, per creature.
    public var sourceRenderChoices: [CreatureRenderChoice]?

    // Custom CodingKeys to map JSON keys to struct properties
    public enum CodingKeys: String, CodingKey {
        case id = "animation_id"
        case title
        case millisecondsPerFrame = "milliseconds_per_frame"
        case note
        case soundFile = "sound_file"
        case numberOfFrames = "number_of_frames"
        case multitrackAudio = "multitrack_audio"
        case sourceScriptId = "source_script_id"
        case sourceScriptTurns = "source_script_turns"
        case sourceStageId = "source_stage_id"
        case sourceStageUpdatedAt = "source_stage_updated_at"
        case sourceStagePlacements = "source_stage_placements"
        case renderSeed = "render_seed"
        case sourceRenderChoices = "source_render_choices"
    }

    public init(
        id: AnimationIdentifier, title: String, millisecondsPerFrame: UInt32,
        note: String, soundFile: String, numberOfFrames: UInt32, multitrackAudio: Bool,
        sourceScriptId: String? = nil, sourceScriptTurns: [DialogScriptTurn]? = nil,
        sourceStageId: String? = nil, sourceStageUpdatedAt: Int64? = nil,
        sourceStagePlacements: [StagePlacement]? = nil, renderSeed: UInt64? = nil,
        sourceRenderChoices: [CreatureRenderChoice]? = nil
    ) {
        self.id = id
        self.title = title
        self.millisecondsPerFrame = millisecondsPerFrame
        self.note = note
        self.soundFile = soundFile
        self.numberOfFrames = numberOfFrames
        self.multitrackAudio = multitrackAudio
        self.sourceScriptId = sourceScriptId
        self.sourceScriptTurns = sourceScriptTurns
        self.sourceStageId = sourceStageId
        self.sourceStageUpdatedAt = sourceStageUpdatedAt
        self.sourceStagePlacements = sourceStagePlacements
        self.renderSeed = renderSeed
        self.sourceRenderChoices = sourceRenderChoices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required by the server's contract, so required here too.
        id = try container.decode(AnimationIdentifier.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        millisecondsPerFrame = try container.decode(UInt32.self, forKey: .millisecondsPerFrame)
        soundFile = try container.decode(String.self, forKey: .soundFile)
        numberOfFrames = try container.decode(UInt32.self, forKey: .numberOfFrames)
        multitrackAudio = try container.decode(Bool.self, forKey: .multitrackAudio)

        // Everything below is omitted by the server when it has no value. An empty string from
        // an older server means the same thing as the key being gone, so both land on `nil`
        // and neither can come back out as a placeholder.
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        sourceScriptId = try Self.nonEmpty(
            container.decodeIfPresent(String.self, forKey: .sourceScriptId))
        sourceScriptTurns = try container.decodeIfPresent(
            [DialogScriptTurn].self, forKey: .sourceScriptTurns)
        sourceStageId = try Self.nonEmpty(
            container.decodeIfPresent(String.self, forKey: .sourceStageId))
        sourceStageUpdatedAt = try container.decodeIfPresent(
            Int64.self, forKey: .sourceStageUpdatedAt)
        sourceStagePlacements = try container.decodeIfPresent(
            [StagePlacement].self, forKey: .sourceStagePlacements)
        renderSeed = try container.decodeIfPresent(UInt64.self, forKey: .renderSeed)
        sourceRenderChoices = try container.decodeIfPresent(
            [CreatureRenderChoice].self, forKey: .sourceRenderChoices)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(millisecondsPerFrame, forKey: .millisecondsPerFrame)
        try container.encode(soundFile, forKey: .soundFile)
        try container.encode(numberOfFrames, forKey: .numberOfFrames)
        try container.encode(multitrackAudio, forKey: .multitrackAudio)

        if !note.isEmpty {
            try container.encode(note, forKey: .note)
        }
        if let sourceScriptId, !sourceScriptId.isEmpty {
            try container.encode(sourceScriptId, forKey: .sourceScriptId)
        }
        if let sourceScriptTurns, !sourceScriptTurns.isEmpty {
            try container.encode(sourceScriptTurns, forKey: .sourceScriptTurns)
        }
        // The server rejects one of these without the other, so they travel as a pair or not
        // at all.
        if let sourceStageId, !sourceStageId.isEmpty, let sourceStageUpdatedAt,
            sourceStageUpdatedAt != 0
        {
            try container.encode(sourceStageId, forKey: .sourceStageId)
            try container.encode(sourceStageUpdatedAt, forKey: .sourceStageUpdatedAt)
        }
        if let sourceStagePlacements, !sourceStagePlacements.isEmpty {
            try container.encode(sourceStagePlacements, forKey: .sourceStagePlacements)
        }
        if let renderSeed, renderSeed != 0 {
            try container.encode(renderSeed, forKey: .renderSeed)
        }
        if let sourceRenderChoices, !sourceRenderChoices.isEmpty {
            try container.encode(sourceRenderChoices, forKey: .sourceRenderChoices)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// The source dialog script's id as a typed `UUID`, or `nil` when there's no live source
    /// (inline render, or the server sent an empty string).
    public var sourceScriptIdentifier: DialogScriptIdentifier? {
        guard let sourceScriptId, !sourceScriptId.isEmpty else { return nil }
        return UUID(uuidString: sourceScriptId)
    }

    /// The source stage's id as a typed `UUID`, or `nil` when the render wasn't stage-bound
    /// (or the server sent an empty string).
    public var sourceStageIdentifier: StageIdentifier? {
        guard let sourceStageId, !sourceStageId.isEmpty else { return nil }
        return UUID(uuidString: sourceStageId)
    }

    /// True when this animation was rendered from a dialog (has a script pointer and/or a
    /// turns snapshot).
    public var hasDialogProvenance: Bool {
        sourceScriptIdentifier != nil || !(sourceScriptTurns?.isEmpty ?? true)
    }


    public static func == (lhs: AnimationMetadata, rhs: AnimationMetadata) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.millisecondsPerFrame == rhs.millisecondsPerFrame && lhs.note == rhs.note
            && lhs.soundFile == rhs.soundFile && lhs.numberOfFrames == rhs.numberOfFrames
            && lhs.multitrackAudio == rhs.multitrackAudio
            && lhs.sourceScriptId == rhs.sourceScriptId
            && lhs.sourceScriptTurns == rhs.sourceScriptTurns
            && lhs.sourceStageId == rhs.sourceStageId
            && lhs.sourceStageUpdatedAt == rhs.sourceStageUpdatedAt
            && lhs.sourceStagePlacements == rhs.sourceStagePlacements
            && lhs.renderSeed == rhs.renderSeed
            && lhs.sourceRenderChoices == rhs.sourceRenderChoices
    }


    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(millisecondsPerFrame)
        hasher.combine(note)
        hasher.combine(soundFile)
        hasher.combine(numberOfFrames)
        hasher.combine(multitrackAudio)
        hasher.combine(sourceScriptId)
        hasher.combine(sourceScriptTurns)
        hasher.combine(sourceStageId)
        hasher.combine(sourceStageUpdatedAt)
        hasher.combine(sourceStagePlacements)
        hasher.combine(renderSeed)
        hasher.combine(sourceRenderChoices)
    }

}


extension AnimationMetadata {

    public static func mock() -> AnimationMetadata {

        let id = DataHelper.generateRandomId()
        let title = "Mock Animation Title"
        let millisecondsPerFrame: UInt32 = 20
        let note = "This is a mock note."
        let soundFile = "mock_sound_file.mp3"
        let numberOfFrames: UInt32 = 100  // Example value
        let multitrackAudio = false  // Defaulting to false

        return AnimationMetadata(
            id: id, title: title,
            millisecondsPerFrame: millisecondsPerFrame, note: note, soundFile: soundFile,
            numberOfFrames: numberOfFrames, multitrackAudio: multitrackAudio)
    }
}
