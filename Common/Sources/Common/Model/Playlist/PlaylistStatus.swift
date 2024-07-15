import Foundation
import Logging

public class PlaylistStatus: Hashable, Equatable, Codable, Identifiable {
    public var universe: UniverseIdentifier
    public var playlist: PlaylistIdentifier
    public var playing: Bool
    public var currentAnimation: AnimationIdentifier

    public init(
        universe: UniverseIdentifier, playlist: PlaylistIdentifier, playing: Bool,
        currentAnimation: AnimationIdentifier
    ) {
        self.universe = universe
        self.playlist = playlist
        self.playing = playing
        self.currentAnimation = currentAnimation
    }

    public static func == (lhs: PlaylistStatus, rhs: PlaylistStatus) -> Bool {
        lhs.universe == rhs.universe && lhs.playlist == rhs.playlist && lhs.playing == rhs.playing
            && lhs.currentAnimation == rhs.currentAnimation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(universe)
        hasher.combine(playlist)
        hasher.combine(playing)
        hasher.combine(currentAnimation)
    }

    enum CodingKeys: String, CodingKey {
        case universe, playlist, playing
        case currentAnimation = "current_animation"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        universe = try container.decode(UniverseIdentifier.self, forKey: .universe)
        playlist = try container.decode(PlaylistIdentifier.self, forKey: .playlist)
        playing = try container.decode(Bool.self, forKey: .playing)
        currentAnimation = try container.decode(AnimationIdentifier.self, forKey: .currentAnimation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(universe, forKey: .universe)
        try container.encode(playlist, forKey: .playlist)
        try container.encode(playing, forKey: .playing)
        try container.encode(currentAnimation, forKey: .currentAnimation)
    }
}

extension PlaylistStatus {
    public static func mock() -> PlaylistStatus {
        return PlaylistStatus(
            universe: Int.random(in: 1...999),  // Generate a random Int for UniverseIdentifier
            playlist: UUID().uuidString,
            playing: false,
            currentAnimation: UUID().uuidString
        )
    }
}
