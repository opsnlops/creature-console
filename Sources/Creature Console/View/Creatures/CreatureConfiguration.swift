
import Foundation
import SwiftUI
import OSLog
import Dispatch
import Common

struct CreatureConfiguration : View {

    @ObservedObject var creature: Creature
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")
    
    init(creature: Creature) {
        self.creature = creature
    }
    
    var body: some View {
        VStack {

            #if os(macOS)
            Form() {
                TextField("Name", text: $creature.name)
                    .disabled(true)
                TextField("Channel Offset", value: $creature.channelOffset, format: .number)
                    .disabled(true)
                TextField("Audio Channel", value: $creature.audioChannel, format: .number)
                    .disabled(true)
            }.padding()
            #endif

            #if os(iOS)
            Form {
                Section(header: Text("Name")) {
                    TextField("", text: $creature.name)
                }
                Section(header: Text("Channel Offset")) {
                    TextField("", value: $creature.channelOffset, format: .number)
                }
                Section(header: Text("Audio Channel")) {
                    TextField("", value: $creature.audioChannel, format: .number)
                }
            }
            #endif


            Text("Inputs")
                .font(.title2)
            InputTable(creature: creature)

            Text("💡 Values may not be changed in the console. To change these values, submit an update from the Controller")
                .padding()
        }

    }
}


struct CreatureConfiguration_Previews: PreviewProvider {
    static var previews: some View {
        CreatureConfiguration(creature: Creature.mock())
    }
}
