//
//  CreatureDetail.swift
//  Creature Console
//
//  Created by April White on 4/6/23.
//

import SwiftUI
import Foundation
import Logging

struct CreatureDetail : View {
    var creatureId : Data
    @ObservedObject var creature: Creature
    @EnvironmentObject var client: CreatureServerClient
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    let logger = Logger(label: "CreatureDetail")
    
    init(creatureId: Data) {
        self.creatureId = creatureId
        self.creature = .mock()
    }
    
    /*
     CreatureDetail()
     Button("Search") {
         Task {
             
             logger.debug("Trying to talk to  \(client.getHostname())")
             do {
                 let serverCreature : Server_Creature? = try await client.searchCreatures(creatureName: a"Beaky1")
                 
                 // If we got somethign back, update the view
                 if let s = serverCreature {
                     creature.updateFromServerCreature(serverCreature: s)
                 }
             
             }
             catch {
                 logger.critical("\( error.localizedDescription)")
                 showErrorAlert = true
                 errorMessage = error.localizedDescription
             }
         }
     }
     .alert(isPresented: $showErrorAlert) {
         Alert(
             title: Text("Oooooh Shit"),
             message: Text(errorMessage),
             dismissButton: .default(Text("Fuck"))
         )
     }
     */
    
    var body: some View {
        
        Group {
            if creature.realData {
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
            else {
                ProgressView("Loading...")
            }
        }.onAppear {
            Task {
                logger.info("Attempting to load creature \(DataHelper.dataToHexString(data: creatureId)) from database...")
                
                do {
                    let serverCreature : Server_Creature? = try await client.getCreature(creatureId: creatureId)
                    
                    // We got data! Update the view!
                    if let s = serverCreature {
                        logger.debug("creature gotten!")
                        creature.updateFromServerCreature(serverCreature: s)
                        creature.realData = true
                    }
                }
                catch {
                    logger.critical("\(error.localizedDescription)")
                    showErrorAlert = true
                    errorMessage = error.localizedDescription
                }
            }
            
        }.alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Oooooh Shit"),
                message: Text(errorMessage),
                dismissButton: .default(Text("Fuck"))
            )
        }
        
        
    }
    
}




struct CreatureDetail_Previews: PreviewProvider {
    static var previews: some View {
        CreatureDetail(creatureId: DataHelper.generateRandomData(byteCount: 12))
    }
}
