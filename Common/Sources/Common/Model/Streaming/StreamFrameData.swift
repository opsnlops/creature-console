import Foundation

/// One frame of live motion data streamed to a creature — sent over the websocket at the
/// event-loop rate (50Hz) while a creature is under live control.
public struct StreamFrameData: Hashable, Equatable, Codable, Sendable {

    public var creatureId: CreatureIdentifier
    public var universe: UniverseIdentifier
    public var data: EncodedFrameData

    public init(
        creatureId: CreatureIdentifier, universe: UniverseIdentifier, data: EncodedFrameData
    ) {
        self.creatureId = creatureId
        self.universe = universe
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case universe
        case data
    }
}


extension StreamFrameData {

    public static func mock() -> StreamFrameData {

        let creatureId: CreatureIdentifier = UUID().uuidString
        let data = DataHelper.generateRandomData(byteCount: 6).base64EncodedString()
        let universe: UniverseIdentifier = 42

        return StreamFrameData(creatureId: creatureId, universe: universe, data: data)
    }
}
