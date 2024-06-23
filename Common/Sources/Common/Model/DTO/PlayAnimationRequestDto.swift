import Foundation

// A simple request to play an animation that the server already knows about
public struct PlayAnimationRequestDto: Codable {
    public var animation_id: AnimationIdentifier
    public var universe: UniverseIdentifier
}
