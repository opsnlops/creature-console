import Common
import OSLog
import SwiftUI

struct ChooseCreatureSheet: View {

    @Environment(\.dismiss) var dismiss
    @ObservedObject var creatureCache = CreatureCache.shared

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "ChooseCreatureSheet")

    @Binding var selectedCreature: Creature?

    var body: some View {
        VStack {
            Picker("Choose a Creature", selection: $selectedCreature) {
                ForEach(creatureCache.creatures.values.sorted(by: { $0.name < $1.name }), id: \.id)
                { creature in
                    Text(creature.name).tag(creature as Creature?)
                }
            }
            .pickerStyle(.automatic)
            .padding()

            HStack {
                Button("Cancel") {
                    selectedCreature = nil
                    dismiss()
                }
                .padding()

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .padding()
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct ChooseCreatureSheet_Previews: PreviewProvider {
    @State static var selectedCreature: Creature? = nil

    static var previews: some View {
        ChooseCreatureSheet(selectedCreature: $selectedCreature)
    }
}
