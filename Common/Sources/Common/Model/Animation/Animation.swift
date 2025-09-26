import Foundation

public final class Animation: Hashable, Equatable, Identifiable, Codable, @unchecked Sendable {

    public var id: AnimationIdentifier
    public var metadata: AnimationMetadata
    public var tracks: [Track] = [] {
        didSet {
            updateNumberOfFrames()
        }
    }

    public init() {
        self.id = UUID().uuidString.lowercased()

        self.metadata = AnimationMetadata(
            id: "",
            title: "",
            lastUpdated: Date(),
            millisecondsPerFrame: 20,
            note: "",
            soundFile: "",
            numberOfFrames: 0,
            multitrackAudio: false
        )

        self.tracks = []

        // Make sure our metadata has our ID in it
        self.metadata.id = self.id
    }

    public init(id: AnimationIdentifier, metadata: AnimationMetadata, tracks: [Track]) {
        self.id = id
        self.metadata = metadata
        self.tracks = tracks

        self.metadata.id = self.id
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

    private func updateNumberOfFrames() {
        // Update the numberOfFrames in metadata to the highest frame count among tracks
        metadata.numberOfFrames = tracks.map { UInt32($0.frames.count) }.max() ?? UInt32(0)
    }
    
    public func recalculateNumberOfFrames() {
        // Recompute to the highest frame count among tracks
        metadata.numberOfFrames = tracks.map { UInt32($0.frames.count) }.max() ?? 0
    }
}

public struct AnimationSnapshot: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: AnimationIdentifier
    public var metadata: AnimationMetadata
    public var tracks: [Track]

    public init(id: AnimationIdentifier, metadata: AnimationMetadata, tracks: [Track]) {
        self.id = id
        self.metadata = metadata
        self.tracks = tracks
    }
}

extension Animation {
    public func snapshot() -> AnimationSnapshot {
        AnimationSnapshot(id: id, metadata: metadata, tracks: tracks)
    }

    public static func from(snapshot: AnimationSnapshot) -> Animation {
        Animation(id: snapshot.id, metadata: snapshot.metadata, tracks: snapshot.tracks)
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
