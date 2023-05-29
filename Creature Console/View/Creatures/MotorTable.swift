//
//  MotorTable.swift
//  Creature Console
//
//  Created by April White on 5/28/23.
//

import SwiftUI

struct MotorTable: View {
    
    var creature : Creature
    
    var body: some View {
        VStack {
            Text("Motors")
                .font(.title2)
            Table(creature.motors) {
                TableColumn("Name") { motor in
                    Text(motor.name)
                }
                TableColumn("Number") { motor in
                    Text(motor.number, format: .number)
                }.width(60)
                TableColumn("Type") { motor in
                    Text(motor.type.description)
                }
                .width(55)
                TableColumn("Min Value") { motor in
                    Text(motor.minValue, format: .number)
                }
                .width(70)
                TableColumn("Max Value") { motor in
                    Text(motor.maxValue, format: .number)
                }
                .width(70)
                TableColumn("Smoothing") { motor in
                    Text(motor.smoothingValue, format: .percent)
                }
                .width(90)
            }
        }
    }
}

struct MotorTable_Previews: PreviewProvider {
    static var previews: some View {
        MotorTable(creature: .mock())
    }
}
