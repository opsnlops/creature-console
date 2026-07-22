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
            "menubarSelectedCreatureId": "",
            "animationFilmingCountdownSeconds": 3,
            "dmxLiveHoldSeconds": 3,
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)

        // Clean up any stale/partial mono preview cache files on launch
        AudioManager.cleanupMonoPreviewCacheOnLaunch()

        // Initialize async components — but not under the test runner, where the host app
        // must stay quiet (issue #38; AppBootstrapper is gated the same way).
        if !TestRun.isActive {
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

            let container = try Self.makeModelContainer(at: storeURL)
            self.modelContainer = container

            // Set the container in the shared data store
            Task {
                await SwiftDataStore.shared.setContainer(container)
            }
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    /// Open the model container, recovering from an un-migratable schema change. The on-disk
    /// store is a disposable cache of server data, so if a structural change can't be migrated
    /// automatically we wipe it and recreate — the app repopulates from the server on launch.
    ///
    /// We wipe up front whenever the model-set fingerprint changed (catches *removed* models,
    /// which SwiftData would otherwise open into a corrupt store without throwing — see
    /// `SwiftDataStoreMigration`), and keep the catch as a last resort for changes that do throw.
    private static func makeModelContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(AppSchema.modelTypes)
        let config = ModelConfiguration(url: storeURL)

        if SwiftDataStoreMigration.needsWipe(storeURL: storeURL, modelTypes: AppSchema.modelTypes) {
            wipeStore(at: storeURL)
        }

        do {
            let container = try ModelContainer(for: schema, configurations: config)
            SwiftDataStoreMigration.recordSignature(
                storeURL: storeURL, modelTypes: AppSchema.modelTypes)
            return container
        } catch {
            wipeStore(at: storeURL)
            let container = try ModelContainer(for: schema, configurations: config)
            SwiftDataStoreMigration.recordSignature(
                storeURL: storeURL, modelTypes: AppSchema.modelTypes)
            return container
        }
    }

    /// Remove the SwiftData store file and its `-shm` / `-wal` sidecars (or the directory).
    private static func wipeStore(at storeURL: URL) {
        let fm = FileManager.default
        let base = storeURL.lastPathComponent
        let parent = storeURL.deletingLastPathComponent()
        for name in [base, base + "-shm", base + "-wal"] {
            try? fm.removeItem(at: parent.appendingPathComponent(name))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(ConsoleStore.shared)
        }
        .modelContainer(modelContainer)
        #if os(macOS) || os(iOS)
            .commands {
                DiagnosticsCommands()
                #if os(macOS)
                    CommandMenu("Caches") {
                        Button("Invalidate Animation Cache...") {
                            CacheInvalidationProcessor.rebuild(.animation)
                        }
                        Button("Invalidate Creature Cache...") {
                            CacheInvalidationProcessor.rebuild(.creature)
                        }
                        Button("Invalidate Playlist Cache...") {
                            CacheInvalidationProcessor.rebuild(.playlist)
                        }
                        Button("Invalidate Sound List Cache...") {
                            CacheInvalidationProcessor.rebuild(.soundList)
                        }
                    }
                    CommandMenu("Utilities") {
                        Button("Generate Lip Sync from WAV…") {
                            LipSyncUtilities.generateLipSyncFromWAV()
                        }
                    }
                #endif
            }
        #endif

        #if os(macOS)
            DebugJoystickScene()
                .environment(ConsoleStore.shared)
            LogViewScene()
                .environment(ConsoleStore.shared)
            AppStateInspectorScene()
                .environment(ConsoleStore.shared)
            SACNUniverseMonitorScene()
                .modelContainer(modelContainer)
                .environment(ConsoleStore.shared)

            Settings {
                SettingsView()
                    .environment(ConsoleStore.shared)
            }

            MenuBarExtra("Creature Control", systemImage: "bird.fill") {
                MenuBarConsoleView()
                    .environment(ConsoleStore.shared)
            }
            .menuBarExtraStyle(.window)
            .modelContainer(modelContainer)
        #endif

        #if os(iOS)
            SACNUniverseMonitorScene()
                .modelContainer(modelContainer)
                .environment(ConsoleStore.shared)
        #endif

    }

    #if os(iOS) || os(tvOS)
        @UIApplicationDelegateAdaptor(ConsoleAppDelegate.self) var appDelegate
    #elseif os(macOS)
        @NSApplicationDelegateAdaptor(ConsoleAppDelegate.self) var appDelegate
    #endif
}
