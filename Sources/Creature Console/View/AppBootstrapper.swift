import Common
import OSLog
import SwiftData
import SwiftUI

actor AppBootstrapper {
    static let shared = AppBootstrapper()
    private var hasStarted = false
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "AppBootstrapper")

    public func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        await AppState.shared.setCurrentActivity(.connectingToServer)

        // Connect websocket immediately so health data starts flowing
        await CreatureServerClient.shared.connectWebsocket(processor: SwiftMessageProcessor.shared)

        // Populate caches in parallel - wait for completion to avoid SwiftData conflicts
        async let creaturesResult = CreatureManager.shared.populateCache()
        async let animationMetadataResult = importAnimationsIntoSwiftData()
        async let playlistsResult = importPlaylistsIntoSwiftData()
        async let soundsResult = importSoundsIntoSwiftData()
        async let fixturesResult = importFixturesIntoSwiftData()
        async let dialogScriptsResult = importDialogScriptsIntoSwiftData()
        async let storyboardsResult = importStoryboardsIntoSwiftData()

        let imports: [(label: String, result: Result<String, any Error>)] = [
            ("Creature cache", (await creaturesResult).mapError { $0 as Error }),
            ("Animation metadata", await animationMetadataResult),
            ("Playlists", await playlistsResult),
            ("Sounds", await soundsResult),
            ("Fixtures", await fixturesResult),
            ("Dialog scripts", await dialogScriptsResult),
            ("Storyboards", await storyboardsResult),
        ]

        let errors = logImportResults(imports)
        if !errors.isEmpty {
            let message =
                "Some data failed to load from server:\n"
                + errors.map { "• \($0)" }.joined(separator: "\n")
                + "\n\nThe app will use cached data if available."
            await AppState.shared.setSystemAlert(show: true, message: message)
        }

        // Now that caches are populated, set to idle
        await AppState.shared.setCurrentActivity(.idle)
    }

    public func refreshCachesAfterWake() async {
        logger.debug("Refreshing caches after wake")

        async let creaturesResult = CreatureManager.shared.populateCache()
        async let animationMetadataResult = importAnimationsIntoSwiftData()
        async let playlistsResult = importPlaylistsIntoSwiftData()
        async let soundsResult = importSoundsIntoSwiftData()
        async let fixturesResult = importFixturesIntoSwiftData()
        async let dialogScriptsResult = importDialogScriptsIntoSwiftData()
        async let storyboardsResult = importStoryboardsIntoSwiftData()

        let imports: [(label: String, result: Result<String, any Error>)] = [
            ("Creature cache", (await creaturesResult).mapError { $0 as Error }),
            ("Animation metadata", await animationMetadataResult),
            ("Playlists", await playlistsResult),
            ("Sounds", await soundsResult),
            ("Fixtures", await fixturesResult),
            ("Dialog scripts", await dialogScriptsResult),
            ("Storyboards", await storyboardsResult),
        ]

        let errors = logImportResults(imports)
        if !errors.isEmpty {
            let message =
                "Some data failed to refresh:\n" + errors.map { "• \($0)" }.joined(separator: "\n")
            await AppState.shared.setSystemAlert(show: true, message: message)
        }
    }

    private func importSoundsIntoSwiftData() async -> Result<String, Error> {
        do {
            let container = await SwiftDataStore.shared.container()
            let importer = SoundImporter(modelContainer: container)
            let server = CreatureServerClient.shared
            let result = await server.listSounds()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                return .success("Imported \(list.count) sounds")
            case .failure(let serverError):
                return .failure(serverError)
            }
        } catch {
            return .failure(error)
        }
    }

    private func importAnimationsIntoSwiftData() async -> Result<String, Error> {
        do {
            let container = await SwiftDataStore.shared.container()
            let importer = AnimationMetadataImporter(modelContainer: container)
            let server = CreatureServerClient.shared
            let result = await server.listAnimations()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                return .success("Imported \(list.count) animations")
            case .failure(let serverError):
                return .failure(serverError)
            }
        } catch {
            return .failure(error)
        }
    }

    private func importPlaylistsIntoSwiftData() async -> Result<String, Error> {
        do {
            let container = await SwiftDataStore.shared.container()
            let importer = PlaylistImporter(modelContainer: container)
            let server = CreatureServerClient.shared
            let result = await server.getAllPlaylists()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                return .success("Imported \(list.count) playlists")
            case .failure(let serverError):
                return .failure(serverError)
            }
        } catch {
            return .failure(error)
        }
    }

    private func importFixturesIntoSwiftData() async -> Result<String, Error> {
        do {
            let container = await SwiftDataStore.shared.container()
            let importer = DmxFixtureImporter(modelContainer: container)
            let server = CreatureServerClient.shared
            let result = await server.getAllFixtures()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                return .success("Imported \(list.count) fixtures")
            case .failure(let serverError):
                return .failure(serverError)
            }
        } catch {
            return .failure(error)
        }
    }

    private func importDialogScriptsIntoSwiftData() async -> Result<String, Error> {
        do {
            let container = await SwiftDataStore.shared.container()
            let importer = DialogScriptImporter(modelContainer: container)
            let server = CreatureServerClient.shared
            let result = await server.listDialogScripts()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                return .success("Imported \(list.count) dialog scripts")
            case .failure(let serverError):
                return .failure(serverError)
            }
        } catch {
            return .failure(error)
        }
    }

    private func importStoryboardsIntoSwiftData() async -> Result<String, Error> {
        do {
            let container = await SwiftDataStore.shared.container()
            let importer = StoryboardImporter(modelContainer: container)
            let server = CreatureServerClient.shared
            let result = await server.listStoryboards()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                return .success("Imported \(list.count) storyboards")
            case .failure(let serverError):
                return .failure(serverError)
            }
        } catch {
            return .failure(error)
        }
    }

    /// Logs each labeled import result and returns the human-readable messages for any that
    /// failed (empty when everything succeeded). Callers decide how to surface the failures.
    private func logImportResults(
        _ imports: [(label: String, result: Result<String, any Error>)]
    ) -> [String] {
        var errors: [String] = []
        for entry in imports {
            switch entry.result {
            case .success(let message):
                logger.debug("\(entry.label): \(message)")
            case .failure(let error):
                logger.warning(
                    "Failed to import \(entry.label): \(error.localizedDescription)")
                errors.append("\(entry.label): \(error.localizedDescription)")
            }
        }
        return errors
    }
}
