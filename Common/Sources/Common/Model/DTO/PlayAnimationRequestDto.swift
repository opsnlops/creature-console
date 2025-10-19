import Foundation

// A simple request to play an animation that the server already knows about
public struct PlayAnimationRequestDto: Codable {
    public var animation_id: AnimationIdentifier
    public var universe: UniverseIdentifier
    public var resumePlaylist: Bool?

    public init(
        animation_id: AnimationIdentifier, universe: UniverseIdentifier, resumePlaylist: Bool? = nil
    ) {
        self.animation_id = animation_id
        self.universe = universe
        self.resumePlaylist = resumePlaylist
    }
}
