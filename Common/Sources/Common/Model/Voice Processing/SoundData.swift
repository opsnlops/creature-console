import Foundation

public struct SoundData: Decodable {
    public struct Metadata: Decodable {
        public let soundFile: String
        public let duration: Double
    }

    public struct MouthCue: Codable {
        public let start: Double
        public let end: Double
        public let value: String

        /// The servo openness for this cue's shape. Delegates to the shared `MouthShape` mapping
        /// so Rhubarb import and dialog-provenance rendering can never drift apart.
        public var intValue: UInt8 { MouthShape.openness(value) }
    }

    public let metadata: Metadata
    public let mouthCues: [MouthCue]
}
