//
//  CreatureDetail.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import SwiftUI
import Foundation

struct CreatureDetail : View {
    @ObservedObject var creature: Creature
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private let isCompact = false
    #endif
    
    
    var body: some View {
        VStack {
            Text(creature.name)
                .font(.title)
                .fontWeight(.bold)
            Text(creature.sacnIP)
                .font(.subheadline)
                .foregroundColor(Color.gray)
                .multilineTextAlignment(.trailing)
            Text("Number of motors: \(creature.numberOfMotors)")
            Table(creature.motors) {
                TableColumn("Name") { motor in
                    Text(motor.name)
                }
                TableColumn("Number") { motor in
                    Text(motor.number, format: .number)
                }.width(40)
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




struct CreatureDetail_Previews: PreviewProvider {
    static var previews: some View {
        CreatureDetail(creature: .mock())
    }
}
