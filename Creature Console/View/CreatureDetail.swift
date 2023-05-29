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
    
    @EnvironmentObject var client : CreatureServerClient
    @EnvironmentObject var eventLoop : EventLoop
    @EnvironmentObject var appState : AppState
    
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    @ObservedObject var creature : Creature
    
    let logger = Logger(label: "CreatureDetail")
    
    var body: some View {
        VStack() {
            
            Text("sACN IP: \(creature.sacnIP)")
            Text("Universe: \(creature.universe)")
            Text("DMX Offset: \(creature.dmxBase)")
            Text("Type: \(creature.type.description)")
            Text("Number of Motors: \(creature.motors.count)")
            
            NavigationLink("Edit") {
                CreatureEdit(creature: creature)
            }
            Spacer()
            
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
        .onDisappear{
            eventLoop.joystick0.removeVirtualJoystickIfNeeded()
        }
        .navigationTitle(creature.name)
#if os(macOS)
        .navigationSubtitle(creature.sacnIP)
#endif
        .toolbar(id: "creatureDetail") {
            ToolbarItem(id: "control", placement: .primaryAction) {
                Button(action: {
                    toggleStreaming()
                }) {
                    Image(systemName: (appState.currentActivity == .streaming) ? "gamecontroller.fill" : "gamecontroller")
                        .foregroundColor((appState.currentActivity == .streaming) ? .green : .primary)
                }
            }
        }
    }
    
    
    
    func toggleStreaming() {
        
        logger.info("Toggling streaming")
        
        if(appState.currentActivity == .idle) {
            
            logger.debug("starting streaming")
            Task {
                DispatchQueue.main.async {
                    appState.currentActivity = .streaming
                }
                do {
                    eventLoop.joystick0.showVirtualJoystickIfNeeded()
                    try await client.streamJoystick(joystick: eventLoop.joystick0, creature: creature)
                } catch {
                    DispatchQueue.main.async {
                        errorMessage = "Unable to start streaming: \(error.localizedDescription)"
                        showErrorAlert = true
                    }
                }
            }
        }
        else {
            // If we're streaming, stop
            if(appState.currentActivity == .streaming) {
            
                logger.debug("stopping streaming")
                client.stopSignalReceived = true
                eventLoop.joystick0.removeVirtualJoystickIfNeeded()
                DispatchQueue.main.async {
                    appState.currentActivity = .idle
                }
                
            }
            else {
                
                DispatchQueue.main.async {
                    errorMessage = "Unable to start streaming while in the \(appState.currentActivity.description) state"
                    showErrorAlert = true
                }
                
            }
        }
    }
}
        
        


struct CreatureDetail_Previews: PreviewProvider {
    static var previews: some View {
        CreatureDetail(creature: .mock())
            .environmentObject(EventLoop.mock())
            .environmentObject(AppState.mock())
    }
}
