import Common
// Needed to configure swift-log (which the Common packages use)
import Logging
import LoggingOSLog
import OSLog
import SwiftData
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

    let modelContainer: ModelContainer

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
            "mouthImportDefaultAxis": 2,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTime": true,
            "logSpareTimeFrameInterval": 1000,
            "useOurJoystick": true,
            "activeUniverse": 1,
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)

        // Clean up any stale/partial mono preview cache files on launch
        AudioManager.cleanupMonoPreviewCacheOnLaunch()

        // Initialize async components
        Task {
            // Make sure the appState is good
            await AppState.shared.setCurrentActivity(.idle)

            // Init the joystick
            await registerJoystickHandlers()

            // Removed the connectingToServer state set here as bootstrapper handles it
        }

        Task { @MainActor in
            MetricKitManager.shared.start()
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

        // Set up SwiftData model container (local file-backed; no CloudKit)
        do {
            let container = try SoundDataStore.createModelContainer()
            self.modelContainer = container

            // Set the container in the actor
            Task {
                await SoundDataStore.shared.setContainer(container)
            }
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
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
                }
                CommandMenu("Diagnostics") {
                    Button("Report Issue…") {
                        let subject = "Creature Console Issue Report"
                        let os = ProcessInfo.processInfo.operatingSystemVersionString
                        let appVersion =
                            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                            ?? "unknown"
                        let build =
                            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
                        let timestamp = ISO8601DateFormatter().string(from: Date())
                        let diagSummary = MetricKitManager.shared.latestSummary(limit: 5)
                        let body = """
                            Please describe what you were doing:

                            App Version: \(appVersion) (\(build))
                            OS: \(os)
                            Timestamp: \(timestamp)


                            Diagnostics Summary:
                            \(diagSummary)
                            """
                        MailComposer.present(subject: subject, body: body)
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
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
