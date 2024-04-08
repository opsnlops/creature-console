
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
    @Published var channelOffset : Int32
    @Published var realData : Bool = false      // Set to true when there's non-mock data loaded
    @Published var notes : String
    @Published var audioChannel : Int32

    init(id: Data, name: String, lastUpdated: Date, channelOffset: Int32, audioChannel: Int32, notes: String) {
        self.id = id
        self.name = name
        self.lastUpdated = lastUpdated
        self.channelOffset = channelOffset
        self.audioChannel = audioChannel
        self.notes = notes
        logger.debug("Created a new Creature from init()")
    }
    
    // Helper that generates a new ID if needed
    convenience init(name: String, lastUpdated: Date, channelOffset: Int32, audioChannel: Int32, notes: String) {
        let id = DataHelper.generateRandomData(byteCount: 12)
        self.init(id: id, name: name, lastUpdated: lastUpdated, channelOffset: channelOffset, audioChannel: audioChannel, notes: notes)
    }
    
    // Creates a new instance from a ProtoBuf object
    convenience init(serverCreature: Server_Creature) {
        
        self.init(id: serverCreature.id,
                  name: serverCreature.name,
                  lastUpdated: TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated),
                  channelOffset: serverCreature.channelOffset,
                  audioChannel: serverCreature.audioChannel,
                  notes: serverCreature.notes)
        
        logger.debug("Created a new Creature from the Server_Creature convenience init-er")
    }
    
    func toServerCreature() -> Server_Creature {
        var s = Server_Creature()
        s.id = self.id
        s.name = self.name
        s.lastUpdated = TimeHelper.dateToTimestamp(date: self.lastUpdated)
        s.channelOffset = self.channelOffset
        s.audioChannel = self.audioChannel
        s.notes = self.notes
        
        return s
    }
    
    /**
     Helper function to return our ID as a `Server_CreatureId`, which is useful when searching for things
     on the server side
     */
    func getIdAsServerCreatureId() -> Server_CreatureId {
        var s = Server_CreatureId()
        s.id = self.id
        
        return s
    }
    
    // hash(into:) function
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(lastUpdated)
        hasher.combine(channelOffset)
        hasher.combine(audioChannel)
        hasher.combine(notes)
        hasher.combine(realData)
    }

    // The == operator
    static func ==(lhs: Creature, rhs: Creature) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.lastUpdated == rhs.lastUpdated &&
               lhs.channelOffset == rhs.channelOffset &&
               lhs.audioChannel == rhs.audioChannel &&
               lhs.notes == rhs.notes &&
               lhs.realData == lhs.realData
    }
    
    func updateFromServerCreature(serverCreature: Server_Creature) {
        self.name = serverCreature.name
        self.channelOffset = serverCreature.channelOffset
        self.lastUpdated = TimeHelper.timestampToDate(timestamp: serverCreature.lastUpdated)
        self.notes = serverCreature.notes
        self.audioChannel = serverCreature.audioChannel
        
    }
    
}


extension Creature {
    static func mock() -> Creature {
        let creature = Creature(id: DataHelper.generateRandomData(byteCount: 12),
            name: "MockCreature",
            lastUpdated: Date(),
            channelOffset: 7,
            audioChannel: 5,
            notes: "Mock Creature Notes")
     
        return creature
    }
}


