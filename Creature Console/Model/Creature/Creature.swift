
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
    @Published var universe : UInt32
    @Published var channelOffset : UInt32
    @Published var numberOfMotors : UInt32
    @Published var type : CreatureType
    @Published var realData : Bool = false      // Set to true when there's non-mock data loaded

    init(id: Data, name: String, type: CreatureType, lastUpdated: Date, universe: UInt32, channelOffset: UInt32, numberOfMotors: UInt32) {
        self.id = id
        self.name = name
        self.type = type
        self.lastUpdated = lastUpdated
        self.universe = universe
        self.channelOffset = channelOffset
        self.numberOfMotors = numberOfMotors
        logger.debug("Created a new Creature from init()")
    }
    
    // Helper that generates a new ID if needed
    convenience init(name: String, type: CreatureType, lastUpdated: Date, universe: UInt32, channelOffset: UInt32, numberOfMotors: UInt32) {
        let id = DataHelper.generateRandomData(byteCount: 12)
        self.init(id: id, name: name, type: type, lastUpdated: lastUpdated, universe: universe, channelOffset: channelOffset, numberOfMotors: numberOfMotors)
    }
    
    // Creates a new instance from a ProtoBuf object
    convenience init(serverCreature: Server_Creature) {
        
        guard let creatureType = CreatureType(protobufValue: serverCreature.type) else {
            // Handle the case where the creature type could not be created. 😬🙅‍♀️🚫🔥
            print("Invalid creature type! Assuming a WLED Light!") // 🚨🔔⚠️💔
            
            self.init(id: serverCreature.id,
                      name: serverCreature.name,
                      type: .wledLight,
                      lastUpdated: TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated),
                      universe: serverCreature.universe,
                      channelOffset: serverCreature.channelOffset,
                      numberOfMotors: serverCreature.numberOfMotors)
            return
            
        }
        
        self.init(id: serverCreature.id,
                  name: serverCreature.name,
                  type: creatureType,
                  lastUpdated: TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated),
                  universe: serverCreature.universe,
                  channelOffset: serverCreature.channelOffset,
                  numberOfMotors: serverCreature.numberOfMotors)
        
        logger.debug("Created a new Creature from the Server_Creature convenience init-er")
    }
    
    // hash(into:) function
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(lastUpdated)
        hasher.combine(universe)
        hasher.combine(channelOffset)
        hasher.combine(numberOfMotors)
        hasher.combine(realData)
    }

    // The == operator
    static func ==(lhs: Creature, rhs: Creature) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.lastUpdated == rhs.lastUpdated &&
               lhs.universe == rhs.universe &&
               lhs.channelOffset == rhs.channelOffset &&
               lhs.numberOfMotors == rhs.numberOfMotors &&
               lhs.realData == rhs.realData
    }
    
    func updateFromServerCreature(serverCreature: Server_Creature) {
        self.name = serverCreature.name
        self.numberOfMotors = serverCreature.numberOfMotors
        self.channelOffset = serverCreature.channelOffset
        self.universe = serverCreature.universe
        self.lastUpdated = TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated)
        
    }
    
}


extension Creature {
    static func mock() -> Creature {
        let creature = Creature(id: DataHelper.generateRandomData(byteCount: 12),
            name: "MockCreature",
            type: .parrot,
            lastUpdated: Date(),
            universe: 666,
            channelOffset: 7,
            numberOfMotors: 12)
     
        return creature
    }
}


