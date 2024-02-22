
import SwiftUI
import Foundation
import OSLog
import Dispatch

struct CreatureDetail : View {
    
    @AppStorage("mfm2023PlaylistHack") private var mfm2023PlaylistHack: String = ""
    
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
        
    @State private var isDoingServerStuff : Bool = false
    @State private var serverMessage : String = ""
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")
    
    var body: some View {
        VStack() {
                        
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
                    creature: creature,
                    joystick: eventLoop.getActiveJoystick()
                    ), label: {
                    Image(systemName: "record.circle")
                })
            }
            ToolbarItem(id: "editCreature", placement: .secondaryAction) {
                NavigationLink(destination: CreatureEdit(creature: creature), label: {
                    Image(systemName: "pencil")
                })
            }
            ToolbarItem(id: "startMFM2023PlaylistPlayback", placement: .secondaryAction) {
                Button(action: {
                    startMFM2023Playlist()
                }) {
                    Image(systemName: "figure.run")
                }
            }
            ToolbarItem(id: "stopPlaylistPlayback", placement: .primaryAction) {
                Button(action: {
                    stopPlaylistPlayback()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }.toolbarRole(.editor)
        .onChange(of: creature){
            logger.info("creature is now \(creature.name)")
            refreshID = creature.name
        }
        .id(refreshID)
        .overlay {
            if isDoingServerStuff {
                Text(serverMessage)
                    .font(.title)
                    .padding()
                    .background(Color.green.opacity(0.4))
                    .cornerRadius(10)
            }
        }
        .onDisappear{
            streamingTask?.cancel()
            
            // Turn off the virtual joystick if it's visible
            if let j = eventLoop.getActiveJoystick() as? SixAxisJoystick {
                j.removeVirtualJoystickIfNeeded()
            }
        }
        .navigationTitle(creature.name)
#if os(macOS)
        .navigationSubtitle(generateStatusString())
#endif
        
    }
    
    
    func generateStatusString() -> String {
        let status =  "Universe \(creature.universe), Offset \(creature.channelOffset)"
       
        return status
    }
    
    func stopPlaylistPlayback() {
        
        logger.info("stopping playlist playback on server")
        serverMessage = "Sending stop playing signal..."
        isDoingServerStuff = true
        
        Task {
            do {
                let result = try await client.stopPlayingPlayist(creatureId: creature.id)
                
                switch(result) {
                case .failure(let value):
                    DispatchQueue.main.async {
                        errorMessage = "Unable to stop playlist playback: \(value)"
                        showErrorAlert = true
                    }
                case .success(let value):
                    logger.info("stopped! \(value)")
                    serverMessage = value
                }
                
            
                
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Unable to stop playlist playback: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
         
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            }
            catch {}
            isDoingServerStuff = false
        }
    }
    
    
    func startMFM2023Playlist() {
        
        logger.info("Doing the gross thing")
        serverMessage = "🤢 Doing the gross thing"
        isDoingServerStuff = true
        
        if let playlistId = DataHelper.stringToOidData(oid: mfm2023PlaylistHack) {
            
            logger.debug("string: \(mfm2023PlaylistHack), data: \(DataHelper.dataToHexString(data: playlistId))")
            
            Task {
                do {
                    let result = try await client.startPlayingPlaylist(creatureId: creature.id, playlistId: playlistId)
                    
                    switch(result) {
                    case .failure(let value):
                        DispatchQueue.main.async {
                            errorMessage = "Unable to start playlist playback: \(value)"
                            showErrorAlert = true
                        }
                    case .success(let value):
                        logger.info("Gross hack accomplished! 🤮! \(value)")
                        serverMessage = value
                    }
                    
                    
                } catch {
                    DispatchQueue.main.async {
                        errorMessage = "Unable to start the gross hack: \(error.localizedDescription)"
                        showErrorAlert = true
                    }
                }
                
                do {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                }
                catch {}
                isDoingServerStuff = false
            }
        }
        else {
            DispatchQueue.main.async {
                errorMessage = "Can't convert \(mfm2023PlaylistHack) to an OID"
                showErrorAlert = true
            }
            
        }
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
                    if let j = eventLoop.getActiveJoystick() as? SixAxisJoystick {
                        j.showVirtualJoystickIfNeeded()
                    }
                    try await client.streamJoystick(joystick: eventLoop.getActiveJoystick(), creature: creature)
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
                
                if let j = eventLoop.getActiveJoystick() as? SixAxisJoystick {
                    j.removeVirtualJoystickIfNeeded()
                }
                
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
            .environmentObject(CreatureServerClient.mock())
    }
}
