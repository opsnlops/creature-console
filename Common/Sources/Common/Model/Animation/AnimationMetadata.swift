import Foundation

/// This is a local version of the `AnimationMetadata` that's sent over the wire
public struct AnimationMetadata: Hashable, Equatable, Codable, Identifiable, Sendable {

    public var id: AnimationIdentifier
    public var title: String
    public var lastUpdated: Date?
    public var millisecondsPerFrame: UInt32 = 20
    public var note: String
    public var soundFile: String
    public var numberOfFrames: UInt32
    public var multitrackAudio: Bool = false


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
    }

    public init(
        id: AnimationIdentifier, title: String, lastUpdated: Date, millisecondsPerFrame: UInt32,
        note: String, soundFile: String, numberOfFrames: UInt32, multitrackAudio: Bool
    ) {
        self.id = id
        self.title = title
        self.lastUpdated = lastUpdated
        self.millisecondsPerFrame = millisecondsPerFrame
        self.note = note
        self.soundFile = soundFile
        self.numberOfFrames = numberOfFrames
        self.multitrackAudio = multitrackAudio
    }


    public static func == (lhs: AnimationMetadata, rhs: AnimationMetadata) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title && lhs.lastUpdated == rhs.lastUpdated
            && lhs.millisecondsPerFrame == rhs.millisecondsPerFrame && lhs.note == rhs.note
            && lhs.soundFile == rhs.soundFile && lhs.numberOfFrames == rhs.numberOfFrames
            && lhs.multitrackAudio == rhs.multitrackAudio
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
