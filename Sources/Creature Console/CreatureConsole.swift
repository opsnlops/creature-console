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
    let joystickManager = JoystickManager.shared
    let statusLights = StatusLightsManager.shared
    let creatureCache = CreatureCache.shared

    init() {
        let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureConsole")

        // Configure swift-log for the Common package
        LoggingSystem.bootstrap(LoggingOSLog.init)

        /**
         Set up default prefs for static things
         */
        let defaultPreferences: [String: Any] = [
            "serverHostname": "server.dev.chirpchirp.dev",
            "serverRestPort": 443,
            "serverUseTLS": true,
            "serverLogsScrollBackLines": 150,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTime": true,
            "logSpareTimeFrameInterval": 1000,
            "audioVolume": 0.8,
            "useOurJoystick": true,
            "activeUniverse": 1,
            "audioFilePath": "file:///Volumes/creatures/sounds"
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)

        // Make sure the appState is good
        appState.currentActivity = .idle

        // Init the joystick
        registerJoystickHandlers(eventLoop: self.eventLoop)

        // Connect to the server
        do {
            appState.currentActivity = .connectingToServer
            try CreatureServerClient.shared.connect(
                serverHostname: UserDefaults.standard.string(forKey: "serverAddress")
                    ?? "127.0.0.1",
                serverPort: UserDefaults.standard.integer(forKey: "serverPort"),
                useTLS: UserDefaults.standard.bool(forKey: "serverUseTLS"))

            logger.info("connected to server")
            appState.currentActivity = .idle

        } catch {
            logger.critical("Error opening server connection: \(error)")
        }

    }

    var body: some Scene {
        WindowGroup {
            TopContentView()
        }

        #if os(macOS)
            DebugJoystickScene()
            LogViewScene()
            AppStateInspectorScene()

            Settings {
                SettingsView()
            }

            MenuBarExtra("Creatures", systemImage: "pawprint.fill") {
                Button("Option 1") {
                    print("Option 1")
                }
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        #endif

    }

    #if os(iOS)
        @UIApplicationDelegateAdaptor(ConsoleAppDelegate.self) var appDelegate
    #elseif os(macOS)
        @NSApplicationDelegateAdaptor(ConsoleAppDelegate.self) var appDelegate
    #endif
}
