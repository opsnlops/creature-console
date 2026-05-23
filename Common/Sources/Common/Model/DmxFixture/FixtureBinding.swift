import Foundation

/// A declarative trigger: when a creature's activity transitions match this binding's
/// filters, the referenced pattern starts on the parent fixture. `nil` for `onReason`
/// or `onState` means "wildcard — match anything".
public struct FixtureBinding: Codable, Hashable, Equatable, Sendable, Identifiable {
    /// Stable client-side identity for ForEach lists. Not sent to the server.
    public var id: UUID
    public var creatureId: CreatureIdentifier
    public var onReason: ActivityReason?
    public var onState: ActivityState?
    public var patternId: FixturePatternIdentifier

    public init(
        id: UUID = UUID(),
        creatureId: CreatureIdentifier,
        onReason: ActivityReason? = nil,
        onState: ActivityState? = nil,
        patternId: FixturePatternIdentifier
    ) {
        self.id = id
        self.creatureId = creatureId
        self.onReason = onReason
        self.onState = onState
        self.patternId = patternId
    }

    public enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case onReason = "on_reason"
        case onState = "on_state"
        case patternId = "pattern_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        self.onReason = try container.decodeIfPresent(ActivityReason.self, forKey: .onReason)
        self.onState = try container.decodeIfPresent(ActivityState.self, forKey: .onState)
        self.patternId = try container.decode(FixturePatternIdentifier.self, forKey: .patternId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encodeIfPresent(onReason, forKey: .onReason)
        try container.encodeIfPresent(onState, forKey: .onState)
        try container.encode(patternId, forKey: .patternId)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(creatureId)
        hasher.combine(onReason)
        hasher.combine(onState)
        hasher.combine(patternId)
    }

    public static func == (lhs: FixtureBinding, rhs: FixtureBinding) -> Bool {
        lhs.creatureId == rhs.creatureId && lhs.onReason == rhs.onReason
            && lhs.onState == rhs.onState && lhs.patternId == rhs.patternId
    }
}
