import Foundation
import Logging

/// This is the representation of a `Creature`
///
/// **IMPORTANT**: This DTO must stay in sync with `CreatureModel` in the GUI package.
/// Any changes to fields here must be reflected in CreatureModel.swift and vice versa.
public final class Creature: Identifiable, Hashable, Equatable, Codable, Sendable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Creature")

    public let id: CreatureIdentifier
    public let name: String
    public let channelOffset: Int
    public let mouthSlot: Int
    public let realData: Bool
    public let audioChannel: Int
    public let inputs: [Input]
    public let speechLoopAnimationIds: [String]
    public let idleAnimationIds: [String]
    public let runtime: CreatureRuntime?

    enum CodingKeys: String, CodingKey {
        case id, name
        case channelOffset = "channel_offset"
        case mouthSlot = "mouth_slot"
        case realData
        case audioChannel = "audio_channel"
        case inputs
        case speechLoopAnimationIds = "speech_loop_animation_ids"
        case idleAnimationIds = "idle_animation_ids"
        case runtime
    }

    public init(
        id: CreatureIdentifier, name: String, channelOffset: Int, mouthSlot: Int, audioChannel: Int,
        inputs: [Input] = [], realData: Bool = false, speechLoopAnimationIds: [String] = [],
        idleAnimationIds: [String] = [], runtime: CreatureRuntime? = nil
    ) {
        self.id = id
        self.name = name
        self.channelOffset = channelOffset
        self.mouthSlot = mouthSlot
        self.audioChannel = audioChannel
        self.realData = realData
        self.inputs = inputs
        self.speechLoopAnimationIds = speechLoopAnimationIds
        self.idleAnimationIds = idleAnimationIds
        self.runtime = runtime
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CreatureIdentifier.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        channelOffset = try container.decode(Int.self, forKey: .channelOffset)
        mouthSlot = try container.decode(Int.self, forKey: .mouthSlot)
        audioChannel = try container.decode(Int.self, forKey: .audioChannel)
        realData = try container.decodeIfPresent(Bool.self, forKey: .realData) ?? false
        inputs = try container.decode([Input].self, forKey: .inputs)
        speechLoopAnimationIds =
            try container.decodeIfPresent([String].self, forKey: .speechLoopAnimationIds) ?? []
        idleAnimationIds =
            try container.decodeIfPresent([String].self, forKey: .idleAnimationIds) ?? []
        runtime = try container.decodeIfPresent(CreatureRuntime.self, forKey: .runtime)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(channelOffset, forKey: .channelOffset)
        try container.encode(mouthSlot, forKey: .mouthSlot)
        try container.encode(audioChannel, forKey: .audioChannel)
        try container.encode(realData, forKey: .realData)
        try container.encode(inputs, forKey: .inputs)
        if !speechLoopAnimationIds.isEmpty {
            try container.encode(speechLoopAnimationIds, forKey: .speechLoopAnimationIds)
        }
        if !idleAnimationIds.isEmpty {
            try container.encode(idleAnimationIds, forKey: .idleAnimationIds)
        }
        try container.encodeIfPresent(runtime, forKey: .runtime)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(channelOffset)
        hasher.combine(mouthSlot)
        hasher.combine(audioChannel)
        hasher.combine(realData)
        hasher.combine(inputs)
        hasher.combine(speechLoopAnimationIds)
        hasher.combine(idleAnimationIds)
        hasher.combine(runtime)
    }

    public static func == (lhs: Creature, rhs: Creature) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.channelOffset == rhs.channelOffset
            && lhs.mouthSlot == rhs.mouthSlot
            && lhs.audioChannel == rhs.audioChannel
            && lhs.realData == rhs.realData
            && lhs.inputs == rhs.inputs
            && lhs.speechLoopAnimationIds == rhs.speechLoopAnimationIds
            && lhs.idleAnimationIds == rhs.idleAnimationIds
            && lhs.runtime == rhs.runtime
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
