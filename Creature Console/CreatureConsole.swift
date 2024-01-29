
import SwiftUI
import OSLog

@main
struct CreatureConsole: App {
    
    var eventLoop : EventLoop
    var appState = AppState()
    var audioManager = AudioManager()

    init() {
        let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureConsole")
        
        // Set up the configuration default
        let defaultPreferences: [String: Any] = [
            "serverAddress": "10.3.2.11",
            "serverPort": 6666,
            "serverLogsScrollBackLines": 50,
            "joystick0.leftThumbstick.xAxis.mapping": 0,
            "joystick0.leftThumbstick.yAxis.mapping": 1,
            "joystick0.rightThumbstick.xAxis.mapping": 2,
            "joystick0.rightThumbstick.yAxis.mapping": 3,
            "joystick0.leftTrigger.mapping": 4,
            "joystick0.rightTrigger.mapping": 5,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTimeFrameInterval": 200,
            "audioVolume": 0.8,
            "useOurJoystick": true,
            "audioFilePath": "file:///Users/april/Library/Mobile%20Documents/com~apple~CloudDocs/creatureSounds/",
            "mfm2023PlaylistHack": "64d81c13568ab1d9860f23b8"
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)
        
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
