
import Foundation
import OSLog



/**
 This is a localized view of a Creature
 
 We need this wrapper so we can make the object observable
 */
class Creature : ObservableObject, Identifiable, Hashable, Equatable, Decodable {
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "Creature")
    var id : String
    @Published var name : String
    @Published var channelOffset : Int
    @Published var realData : Bool = false      // Set to true when there's non-mock data loaded
    @Published var notes : String
    @Published var audioChannel : Int

    // Map our names to what the server is going to give us
    enum CodingKeys: String, CodingKey {
           case id, name, channelOffset = "channel_offset", realData, notes, audioChannel = "audio_channel"
       }


    init(id: String, name: String, channelOffset: Int, audioChannel: Int, notes: String) {
        self.id = id
        self.name = name
        self.channelOffset = channelOffset
        self.audioChannel = audioChannel
        self.notes = notes
        logger.debug("Created a new Creature from init()")
    }
    
    // Helper that generates a new ID if needed
    convenience init(name: String,  channelOffset: Int, audioChannel: Int, notes: String) {
        let id = DataHelper.generateRandomId()
        self.init(id: id, name: name, channelOffset: channelOffset, audioChannel: audioChannel, notes: notes)
    }
    

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        channelOffset = try container.decode(Int.self, forKey: .channelOffset)
        audioChannel = try container.decode(Int.self, forKey: .audioChannel)
        notes = try container.decode(String.self, forKey: .notes)
        realData = try container.decodeIfPresent(Bool.self, forKey: .realData) ?? false
        logger.debug("Decoded a Creature: \(self.name)")
    }


    // hash(into:) function
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(channelOffset)
        hasher.combine(audioChannel)
        hasher.combine(notes)
        hasher.combine(realData)
    }

    // The == operator
    static func ==(lhs: Creature, rhs: Creature) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.channelOffset == rhs.channelOffset &&
               lhs.audioChannel == rhs.audioChannel &&
               lhs.notes == rhs.notes &&
               lhs.realData == rhs.realData
    }

}


extension Creature {
    static func mock() -> Creature {
        let creature = Creature(id: DataHelper.generateRandomId(),
            name: "MockCreature",
            channelOffset: 7,
            audioChannel: 5,
            notes: "Mock Creature Notes")
     
        return creature
    }
}


