import Foundation

/// One full animation that has frame data!
///
/// Most of the time we just use the Metadata
public class Animation: Hashable, Equatable, Identifiable {

    public var id: AnimationIdentifier
    public var metadata: AnimationMetadata
    public var tracks: [TrackIdentifier: Track] = [:]

    public init(id: AnimationIdentifier, metadata: AnimationMetadata, tracks: [TrackIdentifier: Track]) {
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

}

extension Animation {
    public static func mock() -> Animation {

        let id = UUID().uuidString
        let metadata = AnimationMetadata.mock()
        var tracks: [TrackIdentifier: Track] = [:]

        for _ in 0..<5 {
            let sample = Track.mock()
            tracks[sample.id] = sample
        }

        return Animation(id: id, metadata: metadata, tracks: tracks)
    }
}
