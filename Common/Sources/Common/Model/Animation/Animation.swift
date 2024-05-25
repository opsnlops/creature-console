import Combine
import Foundation

/// One full animation that has frame data!
///
/// Most of the time we just use the Metadata
public class Animation: Hashable, Equatable, Identifiable, Codable, ObservableObject {

    @Published public var id: AnimationIdentifier
    @Published public var metadata: AnimationMetadata
    @Published public var tracks: [Track] = []

    public init() {
        self.id = UUID().uuidString

        self.metadata = AnimationMetadata(
            id: UUID().uuidString,
            title: "",
            lastUpdated: Date(),
            millisecondsPerFrame:  20,
            note: "",
            soundFile: "",
            numberOfFrames: 0,
            multitrackAudio: false
        )

        self.tracks = []
    }

    public init(id: AnimationIdentifier, metadata: AnimationMetadata, tracks: [Track]) {
        self.id = id
        self.metadata = metadata
        self.tracks = tracks
    }

    public static func == (lhs: Animation, rhs: Animation) -> Bool {
        lhs.id == rhs.id && lhs.metadata == rhs.metadata && lhs.tracks == rhs.tracks
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(metadata)
        hasher.combine(tracks)
    }

    enum CodingKeys: String, CodingKey {
        case id, metadata, tracks
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AnimationIdentifier.self, forKey: .id)
        metadata = try container.decode(AnimationMetadata.self, forKey: .metadata)
        tracks = try container.decode([Track].self, forKey: .tracks)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.lowercased(), forKey: .id)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(tracks, forKey: .tracks)
    }
}

extension Animation {
    public static func mock() -> Animation {
        let id = UUID().uuidString
        let metadata = AnimationMetadata.mock()
        var tracks: [Track] = []

        for _ in 0..<5 {
            let sample = Track.mock()
            tracks.append(sample)
        }

        return Animation(id: id, metadata: metadata, tracks: tracks)
    }
}
