import Common
import OSLog
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

        async let creaturesResult = CreatureManager.shared.populateCache()
        async let animationMetadataResult = AnimationMetadataCache.shared
            .fetchMetadataListFromServer()
        async let playlistsResult = PlaylistCache.shared.fetchPlaylistsFromServer()
        async let soundsResult = SoundListCache.shared.fetchSoundsFromServer()

        await CreatureServerClient.shared.connectWebsocket(processor: SwiftMessageProcessor.shared)

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
            logger.warning("Failed to populate creature cache: \(error.localizedDescription)")
            errors.append("Creature cache: \(error.localizedDescription)")
        }

        switch results.1 {
        case .success:
            break
        case .failure(let error):
            logger.warning("Failed to fetch animation metadata list: \(error.localizedDescription)")
            errors.append("Animation metadata: \(error.localizedDescription)")
        }

        switch results.2 {
        case .success:
            break
        case .failure(let error):
            logger.warning("Failed to fetch playlists: \(error.localizedDescription)")
            errors.append("Playlists: \(error.localizedDescription)")
        }

        switch results.3 {
        case .success:
            break
        case .failure(let error):
            logger.warning("Failed to fetch sounds: \(error.localizedDescription)")
            errors.append("Sounds: \(error.localizedDescription)")
        }

        if !errors.isEmpty {
            let message =
                "Some data failed to load:\n" + errors.map { "• \($0)" }.joined(separator: "\n")
            await AppState.shared.setSystemAlert(show: true, message: message)
        }

        await AppState.shared.setCurrentActivity(.idle)
    }

    public func refreshCachesAfterWake() async {
        logger.debug("Refreshing caches after wake")

        async let creaturesResult = CreatureManager.shared.populateCache()
        async let animationMetadataResult = AnimationMetadataCache.shared
            .fetchMetadataListFromServer()
        async let playlistsResult = PlaylistCache.shared.fetchPlaylistsFromServer()
        async let soundsResult = SoundListCache.shared.fetchSoundsFromServer()

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
            logger.warning("Failed to fetch sounds after wake: \(error.localizedDescription)")
            errors.append("Sounds: \(error.localizedDescription)")
        }

        if !errors.isEmpty {
            let message =
                "Some data failed to refresh:\n" + errors.map { "• \($0)" }.joined(separator: "\n")
            await AppState.shared.setSystemAlert(show: true, message: message)
        }
    }
}
