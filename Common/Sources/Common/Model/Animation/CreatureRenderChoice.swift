import Foundation

/// Which loops a dialog render actually chose for one creature.
///
/// The renderer picks a speech loop (and optionally an idle loop, entered at a random
/// offset) per creature from that creature's configured lists. Recording the choice makes
/// a render reproducible: together with `AnimationMetadata.renderSeed` it's the whole
/// input to "render this scene again and get the same motion."
///
/// Mirrors the server's `CreatureRenderChoice` (creature-server `AnimationMetadata.cpp`).
/// The server rejects unknown keys here, so this struct is exactly the wire shape.
public struct CreatureRenderChoice: Codable, Equatable, Hashable, Sendable {

    public var creatureId: CreatureIdentifier
    public var speechLoopAnimationId: AnimationIdentifier
    /// The idle loop layered under the speech, if the render used one.
    public var idleAnimationId: AnimationIdentifier?
    /// How far into the idle loop the render started, in frames. Absent means the start.
    public var idleStartOffset: UInt32?

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case speechLoopAnimationId = "speech_loop_animation_id"
        case idleAnimationId = "idle_animation_id"
        case idleStartOffset = "idle_start_offset"
    }

    public init(
        creatureId: CreatureIdentifier,
        speechLoopAnimationId: AnimationIdentifier,
        idleAnimationId: AnimationIdentifier? = nil,
        idleStartOffset: UInt32? = nil
    ) {
        self.creatureId = creatureId
        self.speechLoopAnimationId = speechLoopAnimationId
        self.idleAnimationId = idleAnimationId
        self.idleStartOffset = idleStartOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        speechLoopAnimationId = try container.decode(
            AnimationIdentifier.self, forKey: .speechLoopAnimationId)
        idleAnimationId = try container.decodeIfPresent(
            AnimationIdentifier.self, forKey: .idleAnimationId
        ).flatMap { $0.isEmpty ? nil : $0 }
        idleStartOffset = try container.decodeIfPresent(UInt32.self, forKey: .idleStartOffset)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encode(speechLoopAnimationId, forKey: .speechLoopAnimationId)
        if let idleAnimationId, !idleAnimationId.isEmpty {
            try container.encode(idleAnimationId, forKey: .idleAnimationId)
        }
        try container.encodeIfPresent(idleStartOffset, forKey: .idleStartOffset)
    }
}
