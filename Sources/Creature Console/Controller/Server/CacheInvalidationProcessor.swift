import Common
import Foundation
import OSLog
import SwiftUI

struct CacheInvalidationProcessor {

    static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CacheInvalidationProcessor")

    // TODO: Learn more about Swift 6 😅
    static nonisolated(unsafe) private var loadCeaturesTask: Task<Void, Never>? = nil
    static nonisolated(unsafe) private var loadAnimationsTask: Task<Void, Never>? = nil
    static nonisolated(unsafe) private var loadPlaylistsTask: Task<Void, Never>? = nil
    static nonisolated(unsafe) private var loadSoundListsTask: Task<Void, Never>? = nil


    static func processCacheInvalidation(_ request: CacheInvalidation) {
        switch request.cacheType {
        case .creature:
            rebuildCreatureCache()
        case .animation:
            rebuildAnimationCache()
        case .playlist:
            rebuildPlaylistCache()
        case .soundList:
            rebuildSoundListCache()
        default:
            return

        }
    }


    static func rebuildCreatureCache() {

        logger.info("attempting to rebuild the creature cache")

        let manager = CreatureManager.shared

        loadCeaturesTask?.cancel()

        loadCeaturesTask = Task {
            logger.debug("calling out to the server now...")
            let populateResult = await manager.populateCache()
            switch populateResult {
            case .success:
                logger.debug("the CreatureManager was able to reload the cache!")
            case .failure(let error):
                logger.warning(
                    "unable to get a new copy of the creature list: \(error.localizedDescription)")
                AppState.shared.systemAlertMessage =
                    "Unable to reload the creature cache after getting an invalidation message: \(error.localizedDescription)"
                AppState.shared.showSystemAlert = true
            }
        }

    }

    static func rebuildAnimationCache() {

        logger.info("attempting to rebuild the animation cache")

        let cache = AnimationMetadataCache.shared

        loadAnimationsTask?.cancel()

        loadAnimationsTask = Task {
            logger.debug("telling the cache to rebuild itself...")
            let populateResult = cache.fetchMetadataListFromServer()
            switch populateResult {
            case .success(let message):
                logger.debug("the cache said: \(message)")
            case .failure(let error):
                logger.warning(
                    "unable to get a new copy of the animationMetadata list: \(error.localizedDescription)"
                )
                AppState.shared.systemAlertMessage =
                    "Unable to reload the animation cache after getting an invalidation message: \(error.localizedDescription)"
                AppState.shared.showSystemAlert = true
            }
        }

    }

    static func rebuildPlaylistCache() {

        logger.info("attempting to rebuild the playlist cache")

        let cache = PlaylistCache.shared

        loadPlaylistsTask?.cancel()

        loadPlaylistsTask = Task {
            logger.debug("calling out to the server now...")
            let populateResult = cache.fetchPlaylistsFromServer()
            switch populateResult {
                case .success:
                    logger.debug("rebuilt the playlist cache")
                case .failure(let error):
                    logger.warning(
                        "unable to refresh the playlist cache: \(error.localizedDescription)")
                    AppState.shared.systemAlertMessage =
                    "Unable to reload the playlist cache after getting an invalidation message: \(error.localizedDescription)"
                    AppState.shared.showSystemAlert = true
            }
        }

    }


    static func rebuildSoundListCache() {

        logger.info("attempting to rebuild the sound list cache")

        let cache = SoundListCache.shared

        loadSoundListsTask?.cancel()

        loadSoundListsTask = Task {
            logger.debug("calling out to the server now...")
            let populateResult = cache.fetchSoundsFromServer()
            switch populateResult {
                case .success:
                    logger.info("(re)built the sound list cache")
                case .failure(let error):
                    logger.warning(
                        "unable to refresh the sound list cache: \(error.localizedDescription)")
                    AppState.shared.systemAlertMessage =
                    "Unable to reload the sound list cache after getting an invalidation message: \(error.localizedDescription)"
                    AppState.shared.showSystemAlert = true
            }
        }

    }
}
