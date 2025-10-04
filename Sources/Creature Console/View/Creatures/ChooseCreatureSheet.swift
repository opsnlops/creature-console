import Common
import OSLog
import SwiftData
import SwiftUI

struct ChooseCreatureSheet: View {

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "ChooseCreatureSheet")

    @Binding var selectedCreature: Creature?

    var body: some View {
        VStack {
            Picker("Choose a Creature", selection: $selectedCreature) {
                ForEach(creatures) { creature in
                    Text(creature.name).tag(creature.toDTO() as Creature?)
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
