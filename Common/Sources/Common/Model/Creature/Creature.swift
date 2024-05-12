
import Foundation
import Logging



/**
 This is a localized view of a Creature
 
 We need this wrapper so we can make the object observable
 */
public class Creature : ObservableObject, Identifiable, Hashable, Equatable, Decodable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Creature")
    public var id : CreatureIdentifier
    @Published public var name : String
    @Published public var channelOffset : Int
    @Published public var realData : Bool = false      // Set to true when there's non-mock data loaded
    @Published public var notes : String
    @Published public var audioChannel : Int

    // Map our names to what the server is going to give us
    public enum CodingKeys: String, CodingKey {
           case id, name, channelOffset = "channel_offset", realData, notes, audioChannel = "audio_channel"
       }


    public init(id: CreatureIdentifier, name: String, channelOffset: Int, audioChannel: Int, notes: String) {
        self.id = id
        self.name = name
        self.channelOffset = channelOffset
        self.audioChannel = audioChannel
        self.notes = notes
        logger.debug("Created a new Creature from init()")
    }
    
    // Helper that generates a new ID if needed
    public convenience init(name: String,  channelOffset: Int, audioChannel: Int, notes: String) {
        let id = DataHelper.generateRandomId()
        self.init(id: id, name: name, channelOffset: channelOffset, audioChannel: audioChannel, notes: notes)
    }
    

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CreatureIdentifier.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        channelOffset = try container.decode(Int.self, forKey: .channelOffset)
        audioChannel = try container.decode(Int.self, forKey: .audioChannel)
        notes = try container.decode(String.self, forKey: .notes)
        realData = try container.decodeIfPresent(Bool.self, forKey: .realData) ?? false
        logger.debug("Decoded a Creature: \(self.name)")
    }


    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(channelOffset)
        hasher.combine(audioChannel)
        hasher.combine(notes)
        hasher.combine(realData)
    }

    // The == operator
    public static func ==(lhs: Creature, rhs: Creature) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.channelOffset == rhs.channelOffset &&
               lhs.audioChannel == rhs.audioChannel &&
               lhs.notes == rhs.notes &&
               lhs.realData == rhs.realData
    }

}


extension Creature {
    public static func mock() -> Creature {
        let creature = Creature(id: DataHelper.generateRandomId(),
            name: "MockCreature",
            channelOffset: 7,
            audioChannel: 5,
            notes: "Mock Creature Notes")
     
        return creature
    }
}


