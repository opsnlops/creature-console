import Common
import OSLog
import SwiftUI

struct ChooseCreatureSheet: View {

    @Environment(\.dismiss) var dismiss
    @State private var creatureCacheState = CreatureCacheState(creatures: [:], empty: true)

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "ChooseCreatureSheet")

    @Binding var selectedCreature: Creature?

    var body: some View {
        VStack {
            Picker("Choose a Creature", selection: $selectedCreature) {
                ForEach(
                    creatureCacheState.creatures.values.sorted(by: { $0.name < $1.name }), id: \.id
                ) { creature in
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
        .task {
            // Set initial state from current cache
            let initialState = await CreatureCache.shared.getCurrentState()
            await MainActor.run {
                creatureCacheState = initialState
            }

            // Continue listening for updates
            for await state in await CreatureCache.shared.stateUpdates {
                await MainActor.run {
                    creatureCacheState = state
                }
            }
        }
    }
}

struct ChooseCreatureSheet_Previews: PreviewProvider {
    @State static var selectedCreature: Creature? = nil

    static var previews: some View {
        ChooseCreatureSheet(selectedCreature: $selectedCreature)
    }
}
