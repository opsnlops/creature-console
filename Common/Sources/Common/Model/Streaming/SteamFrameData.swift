import Foundation
import Logging

/// This is a version of the StreamFrameData RPC object
public struct StreamFrameData: Hashable, Equatable, Codable {

    private let logger = Logger(label: "io.opsnlops.CreatureConsole.StreamFrameData")

    public var creatureId: CreatureIdentifier
    public var universe: UniverseIdentifier
    public var data: EncodedFrameData

    public init(ceatureId: CreatureIdentifier, universe: UniverseIdentifier, data: EncodedFrameData)
    {
        self.creatureId = ceatureId
        self.universe = universe
        self.data = data
        logger.trace("Created a new StreamFrameData from init()")
    }


    // Custom CodingKeys to exclude the logger from being encoded/decoded
    private enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case universe
        case data
    }

    public static func == (lhs: StreamFrameData, rhs: StreamFrameData) -> Bool {
        return lhs.creatureId == rhs.creatureId && lhs.universe == rhs.universe
            && lhs.data == rhs.data
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(creatureId)
        hasher.combine(universe)
        hasher.combine(data)
    }
}


extension StreamFrameData {

    public static func mock() -> StreamFrameData {

        let creatureId: CreatureIdentifier = UUID().uuidString
        let data = DataHelper.generateRandomData(byteCount: 6).base64EncodedString()
        let universe: UniverseIdentifier = 42

        return StreamFrameData(ceatureId: creatureId, universe: universe, data: data)
    }
}
