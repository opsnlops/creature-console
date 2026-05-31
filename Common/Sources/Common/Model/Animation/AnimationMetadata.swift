import Foundation

/// This is a local version of the `AnimationMetadata` that's sent over the wire
///
/// **IMPORTANT**: This DTO must stay in sync with `AnimationMetadataModel` in the GUI package.
/// Any changes to fields here must be reflected in AnimationMetadataModel.swift and vice versa.
public struct AnimationMetadata: Hashable, Equatable, Codable, Identifiable, Sendable {

    public var id: AnimationIdentifier
    public var title: String
    public var lastUpdated: Date?
    public var millisecondsPerFrame: UInt32 = 20
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


    // Custom CodingKeys to map JSON keys to struct properties
    public enum CodingKeys: String, CodingKey {
        case id = "animation_id"
        case title
        case lastUpdated = "last_updated"
        case millisecondsPerFrame = "milliseconds_per_frame"
        case note
        case soundFile = "sound_file"
        case numberOfFrames = "number_of_frames"
        case multitrackAudio = "multitrack_audio"
        case sourceScriptId = "source_script_id"
        case sourceScriptTurns = "source_script_turns"
    }

    public init(
        id: AnimationIdentifier, title: String, lastUpdated: Date, millisecondsPerFrame: UInt32,
        note: String, soundFile: String, numberOfFrames: UInt32, multitrackAudio: Bool,
        sourceScriptId: String? = nil, sourceScriptTurns: [DialogScriptTurn]? = nil
    ) {
        self.id = id
        self.title = title
        self.lastUpdated = lastUpdated
        self.millisecondsPerFrame = millisecondsPerFrame
        self.note = note
        self.soundFile = soundFile
        self.numberOfFrames = numberOfFrames
        self.multitrackAudio = multitrackAudio
        self.sourceScriptId = sourceScriptId
        self.sourceScriptTurns = sourceScriptTurns
    }

    /// The source dialog script's id as a typed `UUID`, or `nil` when there's no live source
    /// (inline render, or the server sent an empty string).
    public var sourceScriptIdentifier: DialogScriptIdentifier? {
        guard let sourceScriptId, !sourceScriptId.isEmpty else { return nil }
        return UUID(uuidString: sourceScriptId)
    }

    /// True when this animation was rendered from a dialog (has a script pointer and/or a
    /// turns snapshot).
    public var hasDialogProvenance: Bool {
        sourceScriptIdentifier != nil || !(sourceScriptTurns?.isEmpty ?? true)
    }


    public static func == (lhs: AnimationMetadata, rhs: AnimationMetadata) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title && lhs.lastUpdated == rhs.lastUpdated
            && lhs.millisecondsPerFrame == rhs.millisecondsPerFrame && lhs.note == rhs.note
            && lhs.soundFile == rhs.soundFile && lhs.numberOfFrames == rhs.numberOfFrames
            && lhs.multitrackAudio == rhs.multitrackAudio
            && lhs.sourceScriptId == rhs.sourceScriptId
            && lhs.sourceScriptTurns == rhs.sourceScriptTurns
    }


    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(lastUpdated)
        hasher.combine(millisecondsPerFrame)
        hasher.combine(note)
        hasher.combine(soundFile)
        hasher.combine(numberOfFrames)
        hasher.combine(multitrackAudio)
        hasher.combine(sourceScriptId)
        hasher.combine(sourceScriptTurns)
    }

}


extension AnimationMetadata {

    public static func mock() -> AnimationMetadata {

        let id = DataHelper.generateRandomId()
        let title = "Mock Animation Title"
        let lastUpdated = Date()  // Current date and time
        let millisecondsPerFrame: UInt32 = 20
        let note = "This is a mock note."
        let soundFile = "mock_sound_file.mp3"
        let numberOfFrames: UInt32 = 100  // Example value
        let multitrackAudio = false  // Defaulting to false

        return AnimationMetadata(
            id: id, title: title, lastUpdated: lastUpdated,
            millisecondsPerFrame: millisecondsPerFrame, note: note, soundFile: soundFile,
            numberOfFrames: numberOfFrames, multitrackAudio: multitrackAudio)
    }
}
