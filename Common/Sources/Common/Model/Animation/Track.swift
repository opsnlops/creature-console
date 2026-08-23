import Foundation
import Logging

/// Who a `Track` drives.
///
/// A track has exactly one owner — a creature or a DMX fixture, never both and never
/// neither. The server enforces this (`trackFromJson` rejects a payload where
/// `creature_id` and `fixture_id` are both set or both absent), and modelling it as an
/// enum means the Console can't build an invalid track in the first place.
public enum TrackOwner: Hashable, Equatable, Sendable {
    case creature(CreatureIdentifier)
    case fixture(DmxFixtureIdentifier)
}

/**
 A `Track` is one creature's (or fixture's) set of moments in an animation. There could be several tracks in an animation, or just one. It all depends on who is involved.

 The ``owner`` says which it is. Use ``creatureId`` / ``fixtureId`` to ask about one kind
 specifically; both are `nil` when the track belongs to the other kind.
 */

public struct Track: Hashable, Equatable, Codable, Identifiable, Sendable {

    private static let logger = Logger(label: "io.opsnlops.CreatureConsole.Track")

    // The `id` property to conform to Identifiable
    public var id: TrackIdentifier
    public var owner: TrackOwner
    public var animationId: AnimationIdentifier
    public var frames: [Data]

    /// The creature this track drives, or `nil` when it drives a fixture.
    public var creatureId: CreatureIdentifier? {
        guard case .creature(let id) = owner else { return nil }
        return id
    }

    /// The DMX fixture this track drives, or `nil` when it drives a creature.
    public var fixtureId: DmxFixtureIdentifier? {
        guard case .fixture(let id) = owner else { return nil }
        return id
    }

    public init(
        id: TrackIdentifier, owner: TrackOwner, animationId: AnimationIdentifier, frames: [Data]
    ) {
        self.id = id
        self.owner = owner
        self.animationId = animationId
        self.frames = frames
        Self.logger.trace("Created a new Track from init()")
    }

    /// Convenience for the common case: a track that drives a creature.
    public init(
        id: TrackIdentifier, creatureId: CreatureIdentifier, animationId: AnimationIdentifier,
        frames: [Data]
    ) {
        self.init(id: id, owner: .creature(creatureId), animationId: animationId, frames: frames)
    }

    /// Convenience for a track that drives a DMX fixture.
    public init(
        id: TrackIdentifier, fixtureId: DmxFixtureIdentifier, animationId: AnimationIdentifier,
        frames: [Data]
    ) {
        self.init(id: id, owner: .fixture(fixtureId), animationId: animationId, frames: frames)
    }

    // Enum for CodingKeys
    public enum CodingKeys: String, CodingKey {
        case id = "id"
        case creatureId = "creature_id"
        case animationId = "animation_id"
        case fixtureId = "fixture_id"
        case frames = "frames"
    }

    // Custom Encoder
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)  // Lowercase UUID string
        try container.encode(animationId.lowercased(), forKey: .animationId)  // Lowercase UUID string

        // Exactly one owner key goes out. An empty string is not an accepted stand-in for
        // absent — the server rejects it.
        switch owner {
        case .creature(let creatureId):
            try container.encode(creatureId.lowercased(), forKey: .creatureId)
        case .fixture(let fixtureId):
            try container.encode(fixtureId.lowercased(), forKey: .fixtureId)
        }

        let base64Frames = frames.map { $0.base64EncodedString() }
        try container.encode(base64Frames, forKey: .frames)
    }

    // Custom Decoder
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(TrackIdentifier.self, forKey: .id)
        self.animationId = try container.decode(AnimationIdentifier.self, forKey: .animationId)

        // The server omits the key it doesn't have. Treat an empty string the same as absent,
        // so a legacy document written by an older client still lands on a valid owner.
        let creatureId = try container.decodeIfPresent(CreatureIdentifier.self, forKey: .creatureId)
            .flatMap { $0.isEmpty ? nil : $0 }
        let fixtureId = try container.decodeIfPresent(
            DmxFixtureIdentifier.self, forKey: .fixtureId
        ).flatMap { $0.isEmpty ? nil : $0 }

        switch (creatureId, fixtureId) {
        case (let creatureId?, nil):
            self.owner = .creature(creatureId)
        case (nil, let fixtureId?):
            self.owner = .fixture(fixtureId)
        case (nil, nil):
            throw DecodingError.dataCorruptedError(
                forKey: .creatureId, in: container,
                debugDescription: "A track needs a creature_id or a fixture_id; it had neither.")
        case (_?, _?):
            throw DecodingError.dataCorruptedError(
                forKey: .fixtureId, in: container,
                debugDescription:
                    "A track drives a creature or a fixture, not both; creature_id and fixture_id were both set."
            )
        }

        let base64Frames = try container.decode([String].self, forKey: .frames)
        self.frames = try base64Frames.map {
            guard let data = Data(base64Encoded: $0) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .frames,
                    in: container,
                    debugDescription: "Invalid base64 string for frame data.")
            }
            return data
        }
        Self.logger.trace("Created a new Track from decoder")
    }

    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id && lhs.owner == rhs.owner && lhs.animationId == rhs.animationId
            && lhs.frames.elementsEqual(rhs.frames, by: { $0 == $1 })
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(owner)
        hasher.combine(animationId)
        frames.forEach { hasher.combine($0) }  // Hash each frame's data
    }

}

extension Track {
    public static func mock() -> Track {
        // Generate mock IDs and frame data
        let id = TrackIdentifier()
        let creatureId = CreatureIdentifier(UUID().uuidString.lowercased())  // Random UUID as String
        let animationId = AnimationIdentifier(UUID().uuidString.lowercased())  // Random UUID as String
        let frames = (0..<8).map { _ in Data((0..<7).map { _ in UInt8.random(in: 0...255) }) }  // 8 frames of 7 bytes each
        return Track(id: id, creatureId: creatureId, animationId: animationId, frames: frames)
    }
}


extension Track {

    mutating func replaceAxisData(axisIndex: Int, with byteArray: [UInt8]) {
        guard axisIndex >= 0 && axisIndex < (frames.first?.count ?? 0) else {
            Self.logger.error("Track index out of bounds!")
            return
        }

        for (index, value) in byteArray.enumerated() {
            guard index < frames.count else {
                Self.logger.debug("No more values to replace!")
                break
            }
            var frame = frames[index]
            if axisIndex < frame.count {
                frame[axisIndex] = value
                frames[index] = frame
            }
        }
    }
}
