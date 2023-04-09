//
//  CreatureDetail.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import SwiftUI
import Foundation
import Logging
import Dispatch

struct CreatureDetail : View {
    @ObservedObject var creature: Creature
    @EnvironmentObject var client: CreatureServerClient
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    let logger = Logger(label: "CreatureDetail")
           
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
    





struct CreatureDetail_Previews: PreviewProvider {
    static var previews: some View {
        CreatureDetail(creature: Creature.mock())
    }
}
