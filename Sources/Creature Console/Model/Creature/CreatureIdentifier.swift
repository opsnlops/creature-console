
import Foundation


class CreatureIdentifier : ObservableObject, Identifiable, CustomStringConvertible {
    let id : Data
    let name : String
    
    init(id: Data, name: String) {
        self.id = id
        self.name = name
    }
    
    var description: String {
        return self.name
    }
}


extension CreatureIdentifier {
    static func mock() -> CreatureIdentifier {
        let creatureId = CreatureIdentifier(
            id: DataHelper.generateRandomData(byteCount: 12),
            name: "Mock Creature Id 🤖")
        
        return creatureId
    }
}
