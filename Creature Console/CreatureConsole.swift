
import SwiftUI
import OSLog

@main
struct CreatureConsole: App {
    
    var eventLoop : EventLoop
    var appState = AppState()
    var audioManager = AudioManager()

    init() {
        let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureConsole")
        
        
        /**
         Set up default prefs for static things
         */
        var defaultPreferences: [String: Any] = [
            "serverAddress": "10.19.63.5",
            "serverPort": 6666,
            "serverLogsScrollBackLines": 150,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTime": true,
            "logSpareTimeFrameInterval": 1000,
            "audioVolume": 0.8,
            "useOurJoystick": true,
            "activeUniverse": 1,
            "audioFilePath": "file:///Volumes/creatures/sounds",
            "mfm2023PlaylistHack": "64d81c13568ab1d9860f23b8"
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)
        
        
        // Create the default channel and axis mappings
        let channelAxisMapping = ChannelAxisMapping()
        channelAxisMapping.registerDefaultMappingsAndNames()
        
        
        self.eventLoop = EventLoop(appState: appState)
        self.eventLoop.audioManager = audioManager
        
        // Init the joystick
        registerJoystickHandlers(eventLoop: self.eventLoop)
        
        // Connect to the server
        do {
            CreatureServerClient.shared.appState = appState
            CreatureServerClient.shared.audioManager = audioManager
            try CreatureServerClient.shared.connect(serverHostname: UserDefaults.standard.string(forKey: "serverAddress") ?? "127.0.0.1",
                                                    serverPort: UserDefaults.standard.integer(forKey: "serverPort"))
            logger.info("connected to server")
        } catch {
            print("Error opening connections: \(error)")
        }
    
    }
    
    var body: some Scene {
        WindowGroup {
            TopContentView()
                .environmentObject(CreatureServerClient.shared)
                .environmentObject(eventLoop)
                .environmentObject(audioManager)
                .environmentObject(appState)
        }
        
#if os(macOS)
        DebugJoystickScene(joystick: eventLoop.sixAxisJoystick)
        ACWDebugJoystickScene(joystick: eventLoop.acwJoystick)
        LogViewScene(server: CreatureServerClient.shared)
        Settings {
            SettingsView()
        }
#endif
    
    }
}
