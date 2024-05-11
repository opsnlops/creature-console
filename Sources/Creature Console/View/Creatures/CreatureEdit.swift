
import Foundation
import SwiftUI
import OSLog
import Dispatch
import Common

struct CreatureEdit : View {
 
    @ObservedObject var creature: Creature
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")
    
    init(creature: Creature) {
        self.creature = creature
    }
    
    var body: some View {
        Form() {
            TextField("Name", text: $creature.name)
            TextField("Channel Offset", value: $creature.channelOffset, format: .number)
            TextField("Audio Channel", value: $creature.audioChannel, format: .number)
            TextField("Notes", text: $creature.notes)

        }
        
    }
}


struct CreatureEdit_Previews: PreviewProvider {
    static var previews: some View {
        CreatureEdit(creature: Creature.mock())
    }
}
