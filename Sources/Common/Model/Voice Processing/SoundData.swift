
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

        public var intValue: UInt8 {
                switch value {
                case "A": return 5
                case "B": return 180
                case "C": return 240
                case "D": return 255
                case "E": return 50
                case "F": return 20
                case "X": return 0
                default: return 5 // Default value
                }
            }
        }

    public let metadata: Metadata
    public let mouthCues: [MouthCue]
}
