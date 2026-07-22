import Common
import Dispatch
import Foundation
import OSLog
import SwiftUI

struct CreatureConfiguration: View {

    let creature: Creature

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
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Text("Channel Offset:")
                    .fontWeight(.medium)
                Text(String(creature.channelOffset))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Text("Mouth Slot:")
                    .fontWeight(.medium)
                Text(String(creature.mouthSlot))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if !creature.inputs.isEmpty {
                HStack {
                    Text("Input Channels:")
                        .fontWeight(.medium)
                    Text("\(creature.inputs.count) configured")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }
}


#Preview {
    CreatureConfiguration(creature: Creature.mock())
}
