import Common
// Needed to configure swift-log (which the Common packages use)
import Logging
import LoggingOSLog
import OSLog
import SimpleKeychain
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
    let healthCache = CreatureHealthCache.shared

    let modelContainer: ModelContainer

    init() {
        let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureConsole")

        // Configure swift-log for the Common package
        LoggingSystem.bootstrap(LoggingOSLog.init)

        // Fire up simple keychain to get the proxy's API key if needed
        let simpleKeychain = SimpleKeychain(
            service: "io.opsnlops.CreatureConsole", synchronizable: true)
        logger.debug("SimpleKeychain initialized")

        /**
         Set up default prefs for static things
         */
        let defaultPreferences: [String: Any] = [
            "serverHostname": "server.dev.chirpchirp.dev",
            "serverRestPort": 443,
            "serverUseTLS": true,
            "serverProxyHost": "",
            "useProxy": false,
            "serverLogsScrollBackLines": 150,
            "mouthImportDefaultAxis": 2,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTime": true,
            "logSpareTimeFrameInterval": 1000,
            "useOurJoystick": true,
            "activeUniverse": 1,
            "animationFilmingCountdownSeconds": 3,
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
            // Check if proxy is enabled and get proxy settings
            let useProxy = UserDefaults.standard.bool(forKey: "useProxy")
            var proxyHost: String? = nil
            var apiKey: String? = nil

            if useProxy {
                let proxyHostValue = UserDefaults.standard.string(forKey: "serverProxyHost")
                if let host = proxyHostValue, !host.isEmpty {
                    proxyHost = host
                    // Get API key from keychain
                    apiKey = try? simpleKeychain.string(forKey: "proxyApiKey")

                    if apiKey == nil {
                        logger.warning("Proxy is enabled but no API key found in keychain")
                    }
                }
            }

            try CreatureServerClient.shared.connect(
                serverHostname: UserDefaults.standard.string(forKey: "serverAddress")
                    ?? "127.0.0.1",
                serverPort: UserDefaults.standard.integer(forKey: "serverPort"),
                useTLS: UserDefaults.standard.bool(forKey: "serverUseTLS"),
                serverProxyHost: proxyHost,
                apiKey: apiKey)

            logger.info("server configuration set")

        } catch {
            logger.critical("Error opening server connection: \(error)")
        }

        // Set up SwiftData model container (local file-backed; no CloudKit)
        // Use a single container for all models
        do {
            let fm = FileManager.default
            let appSupport = try fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: true)
            let storeURL = appSupport.appendingPathComponent(
                "CreatureConsoleStore", isDirectory: true)

            let config = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: SoundModel.self, CreatureModel.self, InputModel.self,
                AnimationMetadataModel.self, PlaylistModel.self, PlaylistItemModel.self,
                ServerLogModel.self,
                configurations: config)

            self.modelContainer = container

            // Set the container in the shared data store
            Task {
                await SwiftDataStore.shared.setContainer(container)
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
                    Button("Invalidate Sound List Cache...") {
                        CacheInvalidationProcessor.rebuildSoundListCache()
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
                    Divider()
                    Button("Rebuild All Caches...") {
                        CacheInvalidationProcessor.rebuildAllCaches()
                    }
                }
                CommandMenu("Utilities") {
                    Button("Generate Lip Sync from WAV…") {
                        LipSyncUtilities.generateLipSyncFromWAV()
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
