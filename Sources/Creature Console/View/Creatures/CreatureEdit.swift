
import Foundation
import SwiftUI
import OSLog
import Dispatch

struct CreatureEdit : View {
    @EnvironmentObject var client: CreatureServerClient
    @ObservedObject var creature: Creature
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")
    
    init(creature: Creature) {
        self.creature = creature
    }
    
    var body: some View {
        Form() {
            TextField("Name", text: $creature.name)
            TextField("Universe", value: $creature.universe, format: .number)
            TextField("Channel Offset", value: $creature.channelOffset, format: .number)
            TextField("Number of Motors", value: $creature.numberOfMotors, format: .number)
        }
        
    }
}


struct CreatureEdit_Previews: PreviewProvider {
    static var previews: some View {
        CreatureEdit(creature: Creature.mock())
    }
}
