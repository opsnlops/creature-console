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
            ForEach(creature.motors) { motor in
                Text("Motor #\(motor.number) is type \(motor.type.description)")
            }
            
        }
    }
}

struct CreatureDetail_Previews: PreviewProvider {
    static var previews: some View {
        CreatureDetail(creature: .mock())
    }
}
