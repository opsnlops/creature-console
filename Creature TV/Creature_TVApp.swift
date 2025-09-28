import Common
// Needed to configure swift-log (which the Common packages use)
import Logging
import LoggingOSLog
import OSLog
import SwiftUI

@main
struct Creature_TVApp: App {

    let appState = AppState.shared
    let eventLoop = EventLoop.shared
    let audioManager = AudioManager.shared
    let messageProcessor = SwiftMessageProcessor.shared
    let joystickManager = JoystickManager.shared
    let statusLights = StatusLightsManager.shared
    let creatureCache = CreatureCache.shared
    let healthCache = CreatureHealthCache.shared
    let soundListCache = SoundListCache.shared

    init() {
        let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureConsole")

        // Configure swift-log for the Common package
        LoggingSystem.bootstrap(LoggingOSLog.init)

        /**
         Set up default prefs for static things
         */
        let defaultPreferences: [String: Any] = [
            "serverAddress": "server.prod.chirpchirp.dev",
            "serverPort": 443,
            "serverUseTLS": true,
            "serverLogsScrollBackLines": 150,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTime": true,
            "logSpareTimeFrameInterval": 1000,
            "audioVolume": 0.8,
            "useOurJoystick": true,
            "activeUniverse": 1,
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)

        // Initialize async components
        Task {
            // Make sure the appState is good
            await AppState.shared.setCurrentActivity(.idle)

            // Init the joystick
            await registerJoystickHandlers()
        }

        // Connect to the server
        do {
            try CreatureServerClient.shared.connect(
                serverHostname: UserDefaults.standard.string(forKey: "serverAddress")
                    ?? "127.0.0.1",
                serverPort: UserDefaults.standard.integer(forKey: "serverPort"),
                useTLS: UserDefaults.standard.bool(forKey: "serverUseTLS")
            )

            logger.info("connected to server")
            Task {
                await AppState.shared.setCurrentActivity(.idle)
            }

        } catch {
            logger.critical("Error opening server connection: \(error)")
        }

    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
