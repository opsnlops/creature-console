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
        VStack(alignment: .leading, spacing: 12) {
            // Basic creature information
            HStack {
                Text("Creature ID:")
                    .fontWeight(.medium)
                Text(creature.id)
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                Text("Channel Offset:")
                    .fontWeight(.medium)
                Text(String(creature.channelOffset))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if !creature.inputs.isEmpty {
                HStack {
                    Text("Input Channels:")
                        .fontWeight(.medium)
                    Text("\(creature.inputs.count) configured")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}


struct CreatureConfiguration_Previews: PreviewProvider {
    static var previews: some View {
        CreatureConfiguration(creature: Creature.mock())
    }
}
