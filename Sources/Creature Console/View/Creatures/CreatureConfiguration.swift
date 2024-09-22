import Common
import Dispatch
import Foundation
import OSLog
import SwiftUI

struct CreatureConfiguration: View {

    @ObservedObject var creature: Creature

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureConfiguration")

    init(creature: Creature) {
        self.creature = creature
    }

    var body: some View {
        VStack {

            Text("Inputs")
            InputTable(creature: creature)


            Text(
                "💡 These values may not be changed in the console. To change something, submit an update from the Controller. The Creatures's JSON file is always the source of truth!"
            )
            .padding()
        }

    }
}


struct CreatureConfiguration_Previews: PreviewProvider {
    static var previews: some View {
        CreatureConfiguration(creature: Creature.mock())
    }
}
