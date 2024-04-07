
import Foundation
import OSLog



/**
 This is a localized view of a Creature
 
 We need this wrapper so we can make the object observable
 */
class Creature : ObservableObject, Identifiable, Hashable, Equatable {
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "Creature")
    var id : Data
    @Published var name : String
    @Published var lastUpdated : Date
    @Published var channelOffset : UInt32
    @Published var realData : Bool = false      // Set to true when there's non-mock data loaded

    init(id: Data, name: String, lastUpdated: Date, channelOffset: UInt32) {
        self.id = id
        self.name = name
        self.lastUpdated = lastUpdated
        self.channelOffset = channelOffset
        logger.debug("Created a new Creature from init()")
    }
    
    // Helper that generates a new ID if needed
    convenience init(name: String, lastUpdated: Date, channelOffset: UInt32) {
        let id = DataHelper.generateRandomData(byteCount: 12)
        self.init(id: id, name: name, lastUpdated: lastUpdated, channelOffset: channelOffset)
    }
    
    // Creates a new instance from a ProtoBuf object
    convenience init(serverCreature: Server_Creature) {
        

        self.init(id: serverCreature.id,
                  name: serverCreature.name,
                  lastUpdated: TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated),
                  channelOffset: serverCreature.channelOffset)
        
        logger.debug("Created a new Creature from the Server_Creature convenience init-er")
    }
    
    // hash(into:) function
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(lastUpdated)
        hasher.combine(channelOffset)
        hasher.combine(realData)
    }

    // The == operator
    static func ==(lhs: Creature, rhs: Creature) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.lastUpdated == rhs.lastUpdated &&
               lhs.channelOffset == rhs.channelOffset &&
               lhs.realData == rhs.realData
    }
    
    func updateFromServerCreature(serverCreature: Server_Creature) {
        self.name = serverCreature.name
        self.channelOffset = serverCreature.channelOffset
        self.lastUpdated = TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated)
        
    }
    
}


extension Creature {
    static func mock() -> Creature {
        let creature = Creature(id: DataHelper.generateRandomData(byteCount: 12),
            name: "MockCreature",
            lastUpdated: Date(),
            channelOffset: 7)
     
        return creature
    }
}


