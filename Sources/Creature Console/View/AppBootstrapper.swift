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

        let results = await (
            creaturesResult,
            animationMetadataResult,
            playlistsResult,
            soundsResult
        )

        await handleImportResults(results)

        // Now that caches are populated, set to idle
        await AppState.shared.setCurrentActivity(.idle)
    }

    public func refreshCachesAfterWake() async {
        logger.debug("Refreshing caches after wake")

        async let creaturesResult = CreatureManager.shared.populateCache()
        async let animationMetadataResult = importAnimationsIntoSwiftData()
        async let playlistsResult = importPlaylistsIntoSwiftData()
        async let soundsResult = importSoundsIntoSwiftData()

        let results = await (
            creaturesResult,
            animationMetadataResult,
            playlistsResult,
            soundsResult
        )

        var errors: [String] = []

        switch results.0 {
        case .success:
            break
        case .failure(let error):
            logger.warning(
                "Failed to populate creature cache after wake: \(error.localizedDescription)")
            errors.append("Creature cache: \(error.localizedDescription)")
        }

        switch results.1 {
        case .success:
            break
        case .failure(let error):
            logger.warning(
                "Failed to fetch animation metadata list after wake: \(error.localizedDescription)")
            errors.append("Animation metadata: \(error.localizedDescription)")
        }

        switch results.2 {
        case .success:
            break
        case .failure(let error):
            logger.warning("Failed to fetch playlists after wake: \(error.localizedDescription)")
            errors.append("Playlists: \(error.localizedDescription)")
        }

        switch results.3 {
        case .success:
            break
        case .failure(let error):
            logger.warning("Failed to import sounds after wake: \(error.localizedDescription)")
            errors.append("Sounds: \(error.localizedDescription)")
        }

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

    private func handleImportResults(
        _ results: (
            Result<String, ServerError>,
            Result<String, any Error>,
            Result<String, any Error>,
            Result<String, any Error>
        )
    ) async {
        var errors: [String] = []

        switch results.0 {
        case .success:
            logger.debug("Successfully populated creature cache")
        case .failure(let error):
            logger.warning("Failed to populate creature cache: \(error.localizedDescription)")
            errors.append("Creature cache: \(error.localizedDescription)")
        }

        switch results.1 {
        case .success:
            logger.debug("Successfully imported animation metadata")
        case .failure(let error):
            logger.warning("Failed to fetch animation metadata list: \(error.localizedDescription)")
            errors.append("Animation metadata: \(error.localizedDescription)")
        }

        switch results.2 {
        case .success:
            logger.debug("Successfully imported playlists")
        case .failure(let error):
            logger.warning("Failed to fetch playlists: \(error.localizedDescription)")
            errors.append("Playlists: \(error.localizedDescription)")
        }

        switch results.3 {
        case .success:
            logger.debug("Successfully imported sounds")
        case .failure(let error):
            logger.warning("Failed to import sounds: \(error.localizedDescription)")
            errors.append("Sounds: \(error.localizedDescription)")
        }

        if !errors.isEmpty {
            let message =
                "Some data failed to load from server:\n"
                + errors.map { "• \($0)" }.joined(separator: "\n")
                + "\n\nThe app will use cached data if available."
            await AppState.shared.setSystemAlert(show: true, message: message)
        }
    }
}
