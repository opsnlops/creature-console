
import Foundation
import OSLog

/**
 This is a vesion of the StreamFrameData RPC object
 */
struct StreamFrameData: Hashable, Equatable {
    
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "StreamFrameData")
    
    var ceatureId : String
    var universe : UInt32
    var data : Data
    
    init(ceatureId: String, universe: UInt32, data: Data) {
        self.ceatureId = ceatureId
        self.universe = universe
        self.data = data
        logger.trace("Created a new StreamFrameData from init()")
    }
    
    init(ceatureId: String, universe: UInt32) {
        self.ceatureId = ceatureId
        self.universe = universe
        self.data = Data()
        logger.trace("Created a new StreamFrameData from init()")
    }
    
    // Creates a new instance from a ProtoBuf object
    init(serverStreamFrameData: Server_StreamFrameData) {
        
        self.init(ceatureId: serverStreamFrameData.creatureID,
                  universe: serverStreamFrameData.universe,
                  data: serverStreamFrameData.data)
    }
    
    func toServerStreamFrameData() -> Server_StreamFrameData {
        var packet = Server_StreamFrameData()
        
        packet.creatureID = self.ceatureId
        packet.universe = self.universe
        packet.data = self.data
        
        return packet
    }
    
    static func ==(lhs: StreamFrameData, rhs: StreamFrameData) -> Bool {
        return lhs.ceatureId == rhs.ceatureId &&
               lhs.universe == rhs.universe &&
               lhs.data == rhs.data
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ceatureId)
        hasher.combine(universe)
        hasher.combine(data)
    }
}


extension StreamFrameData {
    
    static func mock() -> StreamFrameData {
    
        let creatureId = DataHelper.generateRandomData(byteCount: 12)
        let data = DataHelper.generateRandomData(byteCount: 6)
        let universe: UInt32 = 42
        
        return StreamFrameData(ceatureId: creatureId, universe: universe, data: data)
    }
}
