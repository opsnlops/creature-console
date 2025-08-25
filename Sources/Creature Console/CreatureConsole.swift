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
            "serverHostname": "server.dev.chirpchirp.dev",
            "serverRestPort": 443,
            "serverUseTLS": true,
            "serverLogsScrollBackLines": 150,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTime": true,
            "logSpareTimeFrameInterval": 1000,
            "audioVolume": 0.8,
            "useOurJoystick": true,
            "activeUniverse": 1
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)

        // Initialize async components
        Task {
            // Make sure the appState is good
            await AppState.shared.setCurrentActivity(.idle)
            
            // Init the joystick
            await registerJoystickHandlers()
            
            // Set connecting state before server connection
            await AppState.shared.setCurrentActivity(.connectingToServer)
        }

        // Connect to the server
        do {
            try CreatureServerClient.shared.connect(
                serverHostname: UserDefaults.standard.string(forKey: "serverAddress")
                    ?? "127.0.0.1",
                serverPort: UserDefaults.standard.integer(forKey: "serverPort"),
                useTLS: UserDefaults.standard.bool(forKey: "serverUseTLS"))

            logger.info("server configuration set")

        } catch {
            logger.critical("Error opening server connection: \(error)")
        }

    }

    var body: some Scene {
        WindowGroup {
            TopContentView()
        }
        #if os(macOS)
        .commands {
            CommandMenu("Caches") {
                Button("Invalidate Animation Cache...") {
                    CacheInvalidationProcessor.rebuildAnimationCache()
                }
                Button("Invalidate Creature Cache...") {
                    CacheInvalidationProcessor.rebuildCreatureCache()
                }
                Button("Invalidate Playlist Cache...") {
                    CacheInvalidationProcessor.rebuildPlaylistCache()
                }
                Button("Invalidate Sound List Cache...") {
                    CacheInvalidationProcessor.rebuildSoundListCache()
                }
            }
        }
        #endif

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

    #if os(iOS) || os(tvOS)
        @UIApplicationDelegateAdaptor(ConsoleAppDelegate.self) var appDelegate
    #elseif os(macOS)
        @NSApplicationDelegateAdaptor(ConsoleAppDelegate.self) var appDelegate
    #endif
}
