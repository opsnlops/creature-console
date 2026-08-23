import Foundation
import Logging

/// This is the representation of a `Creature`
///
/// The `runtime` block is a *server-side view* — what the creature is doing right now — and
/// is never part of a configuration write. ``configurationPayload()`` is what goes to
/// `POST /api/v1/creature`: the config fields only, with every absent optional omitted
/// rather than written as `null`.
///
/// **IMPORTANT**: This DTO must stay in sync with `CreatureModel` in the GUI package.
/// Any changes to fields here must be reflected in CreatureModel.swift and vice versa.
public final class Creature: Identifiable, Hashable, Equatable, Codable, Sendable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Creature")

    public let id: CreatureIdentifier
    public let name: String
    public let channelOffset: Int
    public let mouthSlot: Int
    public let audioChannel: Int
    public let inputs: [Input]
    /// Names the ``Input`` that drives the mouth, overriding ``mouthSlot``. Absent on
    /// creatures that just use the raw slot number.
    public let mouthInput: String?
    public let speechLoopAnimationIds: [String]
    public let idleAnimationIds: [String]
    /// Head-aiming configuration. Absent on creatures that don't aim.
    public let gaze: GazeConfig?
    public let runtime: CreatureRuntime?

    enum CodingKeys: String, CodingKey {
        case id, name
        case channelOffset = "channel_offset"
        case mouthSlot = "mouth_slot"
        case audioChannel = "audio_channel"
        case inputs
        case mouthInput = "mouth_input"
        case speechLoopAnimationIds = "speech_loop_animation_ids"
        case idleAnimationIds = "idle_animation_ids"
        case gaze
        case runtime
    }

    public init(
        id: CreatureIdentifier, name: String, channelOffset: Int, mouthSlot: Int, audioChannel: Int,
        inputs: [Input] = [], mouthInput: String? = nil, speechLoopAnimationIds: [String] = [],
        idleAnimationIds: [String] = [], gaze: GazeConfig? = nil, runtime: CreatureRuntime? = nil
    ) {
        self.id = id
        self.name = name
        self.channelOffset = channelOffset
        self.mouthSlot = mouthSlot
        self.audioChannel = audioChannel
        self.inputs = inputs
        self.mouthInput = mouthInput
        self.speechLoopAnimationIds = speechLoopAnimationIds
        self.idleAnimationIds = idleAnimationIds
        self.gaze = gaze?.isEmpty == true ? nil : gaze
        self.runtime = runtime
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CreatureIdentifier.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        channelOffset = try container.decode(Int.self, forKey: .channelOffset)
        mouthSlot = try container.decode(Int.self, forKey: .mouthSlot)
        audioChannel = try container.decode(Int.self, forKey: .audioChannel)

        // Everything below is optional on the wire. `decodeIfPresent` maps both a missing key
        // and an explicit `null` to `nil`, which is what makes a legacy oat++ response with
        // null placeholders decode the same as a clean 3.45.0 one. An empty string is treated
        // as absent too, so nothing can come back out as a placeholder.
        inputs = try container.decodeIfPresent([Input].self, forKey: .inputs) ?? []
        mouthInput = try container.decodeIfPresent(String.self, forKey: .mouthInput)
            .flatMap { $0.isEmpty ? nil : $0 }
        speechLoopAnimationIds =
            try container.decodeIfPresent([String].self, forKey: .speechLoopAnimationIds) ?? []
        idleAnimationIds =
            try container.decodeIfPresent([String].self, forKey: .idleAnimationIds) ?? []
        let decodedGaze = try container.decodeIfPresent(GazeConfig.self, forKey: .gaze)
        gaze = decodedGaze?.isEmpty == true ? nil : decodedGaze
        runtime = try container.decodeIfPresent(CreatureRuntime.self, forKey: .runtime)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeConfiguration(into: &container)
        try container.encodeIfPresent(runtime, forKey: .runtime)
    }

    /// Encode just the configuration — everything the server's creature codec accepts, and
    /// nothing else. Shared by ``encode(to:)`` and ``configurationPayload()`` so the two can't
    /// drift.
    fileprivate func encodeConfiguration(
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(channelOffset, forKey: .channelOffset)
        try container.encode(mouthSlot, forKey: .mouthSlot)
        try container.encode(audioChannel, forKey: .audioChannel)
        try container.encode(inputs, forKey: .inputs)

        if let mouthInput, !mouthInput.isEmpty {
            try container.encode(mouthInput, forKey: .mouthInput)
        }
        if !speechLoopAnimationIds.isEmpty {
            try container.encode(speechLoopAnimationIds, forKey: .speechLoopAnimationIds)
        }
        if !idleAnimationIds.isEmpty {
            try container.encode(idleAnimationIds, forKey: .idleAnimationIds)
        }
        if let gaze, !gaze.isEmpty {
            try container.encode(gaze, forKey: .gaze)
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(channelOffset)
        hasher.combine(mouthSlot)
        hasher.combine(audioChannel)
        hasher.combine(inputs)
        hasher.combine(mouthInput)
        hasher.combine(speechLoopAnimationIds)
        hasher.combine(idleAnimationIds)
        hasher.combine(gaze)
        hasher.combine(runtime)
    }

    public static func == (lhs: Creature, rhs: Creature) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.channelOffset == rhs.channelOffset
            && lhs.mouthSlot == rhs.mouthSlot
            && lhs.audioChannel == rhs.audioChannel
            && lhs.inputs == rhs.inputs
            && lhs.mouthInput == rhs.mouthInput
            && lhs.speechLoopAnimationIds == rhs.speechLoopAnimationIds
            && lhs.idleAnimationIds == rhs.idleAnimationIds
            && lhs.gaze == rhs.gaze
            && lhs.runtime == rhs.runtime
    }
}


extension Creature {

    /// The body for `POST /api/v1/creature` — configuration only, no `runtime`.
    ///
    /// The runtime block is the server's own view of what this creature is doing; echoing it
    /// back in a config write would be the Console asserting state it doesn't own.
    public func configurationPayload() -> CreatureConfigurationPayload {
        CreatureConfigurationPayload(creature: self)
    }

    /// The resolved mouth slot: the slot of the input ``mouthInput`` names, falling back to
    /// ``mouthSlot`` when there's no override (or it names an input this creature doesn't
    /// have). Mirrors the server's `resolvedMouthSlot`.
    public var resolvedMouthSlot: Int {
        guard let mouthInput, !mouthInput.isEmpty,
            let input = inputs.first(where: { $0.name == mouthInput })
        else { return mouthSlot }
        return Int(input.slot)
    }
}


/// A `Creature` narrowed to just the fields the server accepts in a configuration write.
///
/// This exists so the wire model and the UI model can't drift into each other: encoding a
/// `Creature` for display purposes and encoding one for a POST are different jobs, and only
/// this type does the second one.
public struct CreatureConfigurationPayload: Encodable, Sendable {
    private let creature: Creature

    init(creature: Creature) {
        self.creature = creature
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Creature.CodingKeys.self)
        try creature.encodeConfiguration(into: &container)
    }
}


extension Creature {
    public static func mock() -> Creature {
        let creature = Creature(
            id: UUID().uuidString,
            name: "MockCreature",
            channelOffset: 7,
            mouthSlot: 2,
            audioChannel: 5,
            inputs: [
                Input(name: "MockInput", slot: 1, width: 1, joystickAxis: 1),
                Input(name: "Input 2", slot: 2, width: 2, joystickAxis: 2),
            ],
            speechLoopAnimationIds: ["speech-loop-1"],
            idleAnimationIds: ["idle-loop-1"]
        )

        return creature
    }
}
