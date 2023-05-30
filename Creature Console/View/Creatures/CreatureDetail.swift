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
    @State private var streamingTask: Task<Void, Never>? = nil
    
    @ObservedObject var creature : Creature
    
    // Reassign the ID every time we load a new creature to force
    // SwiftUI to rebuild the view
    @State private var refreshID = UUID().uuidString  // Start with a UUID since creature may not exist the first time
        
    let logger = Logger(label: "CreatureDetail")
    
    var body: some View {
        VStack() {
            
            Text("sACN IP: \(creature.sacnIP)")
            Text("Universe: \(creature.universe)")
            Text("DMX Offset: \(creature.dmxBase)")
            Text("Type: \(creature.type.description)")
            Text("Number of Motors: \(creature.motors.count)")

            Spacer()
            
            AnimationTable(creature: creature)
            
        }
        .toolbar(id: "\(creature.name) creatureDetail") {
            ToolbarItem(id: "control", placement: .primaryAction) {
                Button(action: {
                    toggleStreaming()
                }) {
                    Image(systemName: (appState.currentActivity == .streaming) ? "gamecontroller.fill" : "gamecontroller")
                        .foregroundColor((appState.currentActivity == .streaming) ? .green : .primary)
                }
            }
            ToolbarItem(id: "recordAnimation", placement: .secondaryAction) {
                NavigationLink(destination: RecordAnimation(
                    joystick: eventLoop.joystick0,
                    creature: creature), label: {
                    Image(systemName: "record.circle")
                })
            }
            ToolbarItem(id: "editCreature", placement: .secondaryAction) {
                NavigationLink(destination: CreatureEdit(creature: creature), label: {
                    Image(systemName: "pencil")
                })
            }
        }.toolbarRole(.editor)
        .onChange(of: creature){ _ in
            logger.info("creature is now \(creature.name)")
            refreshID = creature.name
        }
        .id(refreshID)
        .onDisappear{
            streamingTask?.cancel()
            eventLoop.joystick0.removeVirtualJoystickIfNeeded()
        }
        .navigationTitle(creature.name)
#if os(macOS)
        .navigationSubtitle(creature.sacnIP)
#endif
        
    }
    
    
    func toggleStreaming() {
        
        logger.info("Toggling streaming")
        
        if(appState.currentActivity == .idle) {
            
            logger.debug("starting streaming")
            streamingTask?.cancel()
            streamingTask = Task {
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
                streamingTask?.cancel()
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
