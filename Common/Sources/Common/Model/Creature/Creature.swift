import Foundation
import Logging

/// This is the representation of a `Creature`
public class Creature: ObservableObject, Identifiable, Hashable, Equatable, Codable {
    private var logger = Logger(label: "io.opsnlops.CreatureConsole.Creature")

    public let id: CreatureIdentifier
    @Published public var name: String
    @Published public var channelOffset: Int
    @Published public var realData: Bool
    @Published public var audioChannel: Int
    @Published public var inputs: [Input]

    enum CodingKeys: String, CodingKey {
        case id, name
        case channelOffset = "channel_offset"
        case realData
        case audioChannel = "audio_channel"
        case inputs
    }

    public init(
        id: CreatureIdentifier, name: String, channelOffset: Int, audioChannel: Int,
        inputs: [Input] = [], realData: Bool = false
    ) {
        self.id = id
        self.name = name
        self.channelOffset = channelOffset
        self.audioChannel = audioChannel
        self.realData = realData
        self.inputs = inputs
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CreatureIdentifier.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        channelOffset = try container.decode(Int.self, forKey: .channelOffset)
        audioChannel = try container.decode(Int.self, forKey: .audioChannel)
        realData = try container.decodeIfPresent(Bool.self, forKey: .realData) ?? false
        inputs = try container.decode([Input].self, forKey: .inputs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(channelOffset, forKey: .channelOffset)
        try container.encode(audioChannel, forKey: .audioChannel)
        try container.encode(realData, forKey: .realData)
        try container.encode(inputs, forKey: .inputs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(channelOffset)
        hasher.combine(audioChannel)
        hasher.combine(realData)
        hasher.combine(inputs)
    }

    public static func == (lhs: Creature, rhs: Creature) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.channelOffset == rhs.channelOffset
            && lhs.audioChannel == rhs.audioChannel
            && lhs.realData == rhs.realData
            && lhs.inputs == rhs.inputs
    }
}


extension Creature {
    public static func mock() -> Creature {
        let creature = Creature(
            id: UUID().uuidString,
            name: "MockCreature",
            channelOffset: 7,
            audioChannel: 5,
            inputs: [
                Input(name: "MockInput", slot: 1, width: 1, joystickAxis: 1),
                Input(name: "Input 2", slot: 2, width: 2, joystickAxis: 2),
            ]
        )

        return creature
    }
}
