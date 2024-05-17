import Common
// Needed to configure swift-log (which the Common packages use)
import Logging
import LoggingOSLog
import OSLog
import SwiftUI

@main
struct CreatureConsole: App {

    let appState = AppState.shared
    let eventLoop = EventLoop.shared
    let audioManager = AudioManager.shared
    let messageProcessor = SwiftMessageProcessor.shared

    init() {
        let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureConsole")

        // Configure swift-log for the Common package
        LoggingSystem.bootstrap(LoggingOSLog.init)

        /**
         Set up default prefs for static things
         */
        let defaultPreferences: [String: Any] = [
            "serverAddress": "10.19.63.5",  // gRPC
            "serverPort": 6666,  // gRPC
            "serverHostname": "localhost",  // REST
            "serverRestPort": 3000,  // REST
            "serverUseTLS": false,  // REST
            "serverLogsScrollBackLines": 150,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTime": true,
            "logSpareTimeFrameInterval": 1000,
            "audioVolume": 0.8,
            "useOurJoystick": true,
            "activeUniverse": 1,
            "audioFilePath": "file:///Volumes/creatures/sounds",
            "mfm2023PlaylistHack": "64d81c13568ab1d9860f23b8",
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)


        // Create the default channel and axis mappings
        let channelAxisMapping = ChannelAxisMapping()
        channelAxisMapping.registerDefaultMappingsAndNames()


        // Make sure the appState is good
        appState.currentActivity = .idle

        // Init the joystick
        registerJoystickHandlers(eventLoop: self.eventLoop)

        // Connect to the server
        do {
            try CreatureServerClient.shared.connect(
                serverHostname: UserDefaults.standard.string(forKey: "serverAddress")
                    ?? "127.0.0.1",
                serverPort: UserDefaults.standard.integer(forKey: "serverPort"))
            logger.info("connected to server")

        } catch {
            print("Error opening connections: \(error)")
        }

    }

    var body: some Scene {
        WindowGroup {
            TopContentView()
        }

        #if os(macOS)
            DebugJoystickScene(joystick: eventLoop.sixAxisJoystick)
            ACWDebugJoystickScene(joystick: eventLoop.acwJoystick)
            LogViewScene()
            Settings {
                SettingsView()
            }
        #endif

    }

    #if os(iOS)
        @UIApplicationDelegateAdaptor(ConsoleAppDelegate.self) var appDelegate
    #elseif os(macOS)
        @NSApplicationDelegateAdaptor(ConsoleAppDelegate.self) var appDelegate
    #endif
}
