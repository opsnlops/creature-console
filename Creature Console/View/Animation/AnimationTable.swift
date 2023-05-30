//
//  AnimationTable.swift
//  Creature Console
//
//  Created by April White on 5/29/23.
//

import SwiftUI
import Logging

struct AnimationTable: View {
    
    @EnvironmentObject var client: CreatureServerClient
    @EnvironmentObject var eventLoop : EventLoop
    @ObservedObject var creature: Creature
    
    @State var animationIds : [AnimationIdentifier]?

    let logger = Logger(label: "Animation Table")
    
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var selection: AnimationIdentifier.ID? {
        didSet {
            logger.info("selected is now \(String(describing: selection))")
        }
    }
    
    @State private var loadDataTask: Task<Void, Never>? = nil
    
    
    var body: some View {
        VStack {
            Text("Animations")
                .font(.title3)
            
            if let animationIds = animationIds {
                
                Table(animationIds, selection: $selection) {
                    TableColumn("Name") { a in
                        Text(a.metadata.title)
                    }
                    .width(min: 120, ideal: 250)
                    TableColumn("Frames") { a in
                        Text(a.metadata.numberOfFrames, format: .number)
                    }
                    .width(60)
                    TableColumn("Period") { a in
                        Text("\(a.metadata.millisecondsPerFrame)ms")
                    }
                    .width(55)
                    TableColumn("Audio") { a in
                        Text(a.metadata.soundFile)
                    }
                    TableColumn("Time (ms)") { a in
                        Text(a.metadata.milliseconds, format: .number)
                    }
                    .width(80)
                }
                .contextMenu(forSelectionType: AnimationIdentifier.ID.self) { a in
                    if a.isEmpty {
                        NavigationLink(destination: RecordAnimation(
                            joystick: eventLoop.joystick0,
                            creature: creature), label: {
                                Label("Record new Animation", systemImage: "record.circle")
                            })
                    } else {
                        Button {
                            // Add this item to a list of favorites.
                        } label: {
                            Label("Play Sound File \(a.description)", systemImage: "music.quarternote.3")
                        }
                        Button {
                            // Add this item to a list of favorites."
                        } label: {
                            Label("Play Locally", systemImage: "play.fill")
                        }
                        Button {
                            // Add this item to a list of favorites.
                        } label: {
                            Label("Play on Server", systemImage: "play")
                        }
                        
                        NavigationLink(destination: AnimationEditor(
                            animationId: selection,
                            creature: creature), label: {
                                Label("Edit Animation", systemImage: "pencil")
                            })
                    }
                    
                    
                }
            }
            else {
                ProgressView("Loading animations for \(creature.name)")
                    .padding()
            }
        }
        .onAppear {
            logger.debug("onAppear()")
            loadData()
        }
        .onDisappear {
            loadDataTask?.cancel()
        }
        .onChange(of: creature) { _ in
            logger.info("onChange() in AnimationTable")
            loadData()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Unable to load Animations"),
                message: Text(alertMessage),
                dismissButton: .default(Text("Fiiiiiine"))
            )
        }
    }
    
    
    func loadData() {
        
        loadDataTask?.cancel()
                
        loadDataTask = Task {
            // Go load the animations
            let pValue = creature.type.protobufValue
            let result = await client.listAnimations(creatureType: pValue)
            logger.debug("Loaded animations for \(creature.name)")
            
            switch(result) {
            case .success(let data):
                logger.debug("success!")
                self.animationIds = data
            case .failure(let error):
                alertMessage = "Error: \(String(describing: error.errorDescription))"
                logger.warning("Unable to load the animations for \(creature.name): \(String(describing: error.errorDescription))")
                showErrorAlert = true
            }
        }
    }
}

struct AnimationTable_Previews: PreviewProvider {
    static var previews: some View {
        AnimationTable(creature: .mock(),
                       animationIds: [.mock(), .mock(), .mock()])
    }
}



/*
 
 */
