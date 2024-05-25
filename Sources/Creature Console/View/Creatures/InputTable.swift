import Foundation
import SwiftUI
import OSLog
import Common

struct InputTable: View {

    var creature: Creature

    let numberFormatter = Decimal.FormatStyle.number

    var body: some View {

        if creature.inputs.isEmpty {
            Text("Creature has no inputs defined")
        }
        else
        {
            Table(creature.inputs) {
                TableColumn("Name", value: \.name)
                    .width(min: 120, ideal: 200)
                TableColumn("Slot") { input in
                    Text(input.slot.formatted(.number))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 20, ideal: 40)
                TableColumn("Width") { input in
                    Text(input.width.formatted(.number))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 20, ideal: 40)
                TableColumn("Joystick Axis") { input in
                    Text(input.joystickAxis.formatted(.number))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 20, ideal: 40)
            }
        }

    }

}

#Preview {
    InputTable(creature: Creature.mock())
}
