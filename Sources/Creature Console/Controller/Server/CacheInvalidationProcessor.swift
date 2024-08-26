import Common
import Foundation
import OSLog
import SwiftUI

struct CacheInvalidationProcessor {

    static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CacheInvalidationProcessor")

    static func processCacheInvalidation(_ request: CacheInvalidation) {
        switch request.cacheType {
        case .creature:
            rebuildCreatureCache()
        case .animation:
            rebuildAnimationCache()
        case .playlist:
            rebuildPlaylistCache()
        default:
            return

        }
    }


    static func rebuildCreatureCache() {

        logger.info("attempting to rebuild the creature cache")

        let manager = CreatureManager.shared

        Task {
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

        Task {
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

        Task {
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
}
