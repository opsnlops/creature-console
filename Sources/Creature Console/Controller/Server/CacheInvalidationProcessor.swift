import Common
import Foundation
import OSLog
import SwiftData
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
            rebuildCreatureCache(deleteStaleEntries: true)
        case .animation:
            rebuildAnimationCache(deleteStaleEntries: true)
        case .playlist:
            rebuildPlaylistCache(deleteStaleEntries: true)
        case .soundList:
            rebuildSoundListCache(deleteStaleEntries: true)
        case .adHocAnimationList:
            logger.info("ad-hoc animation cache invalidation received - refresh handler pending")
        case .adHocSoundList:
            logger.info("ad-hoc sound cache invalidation received - refresh handler pending")
        default:
            return

        }
    }


    // Async version that can be awaited for sequential execution
    private static func rebuildCreatureCacheAsync(deleteStaleEntries: Bool = false) async {
        logger.debug("calling out to the server now...")
        let server = CreatureServerClient.shared
        let result = await server.getAllCreatures()
        switch result {
        case .success(let creatures):
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = CreatureImporter(modelContainer: container)

                // Optionally delete entries not in the server response
                if deleteStaleEntries {
                    let ids = Set(creatures.map { $0.id })
                    try await importer.deleteAllExcept(ids: ids)
                    logger.debug("deleted stale creature entries not in server response")
                }

                try await importer.upsertBatch(creatures)
                logger.info(
                    "(re)built the creature cache in SwiftData: imported \(creatures.count) creatures"
                )
            } catch {
                logger.warning(
                    "unable to import creatures into SwiftData: \(error.localizedDescription)")
                await AppState.shared.setSystemAlert(
                    show: true,
                    message:
                        "Unable to reload the creature cache after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            logger.warning(
                "unable to fetch creatures from server: \(error.localizedDescription)")
            await AppState.shared.setSystemAlert(
                show: true,
                message:
                    "Unable to fetch creatures after invalidation: \(error.localizedDescription)"
            )
        }
    }

    static func rebuildCreatureCache(deleteStaleEntries: Bool = false) {
        logger.info("attempting to rebuild the creature cache (SwiftData import)")

        loadCeaturesTask?.cancel()

        loadCeaturesTask = Task {
            await rebuildCreatureCacheAsync(deleteStaleEntries: deleteStaleEntries)
        }
    }

    // Async version that can be awaited for sequential execution
    private static func rebuildAnimationCacheAsync(deleteStaleEntries: Bool = false) async {
        logger.debug("calling out to the server now...")
        let server = CreatureServerClient.shared
        let result = await server.listAnimations()
        switch result {
        case .success(let animations):
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = AnimationMetadataImporter(modelContainer: container)

                // Optionally delete entries not in the server response
                if deleteStaleEntries {
                    let ids = Set(animations.map { $0.id })
                    try await importer.deleteAllExcept(ids: ids)
                    logger.debug("deleted stale animation entries not in server response")
                }

                try await importer.upsertBatch(animations)
                logger.info(
                    "(re)built the animation cache in SwiftData: imported \(animations.count) animations"
                )
            } catch {
                logger.warning(
                    "unable to import animations into SwiftData: \(error.localizedDescription)")
                await AppState.shared.setSystemAlert(
                    show: true,
                    message:
                        "Unable to reload the animation cache after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            logger.warning(
                "unable to fetch animations from server: \(error.localizedDescription)")
            await AppState.shared.setSystemAlert(
                show: true,
                message:
                    "Unable to fetch animations after invalidation: \(error.localizedDescription)"
            )
        }
    }

    static func rebuildAnimationCache(deleteStaleEntries: Bool = false) {
        logger.info("attempting to rebuild the animation cache (SwiftData import)")

        loadAnimationsTask?.cancel()

        loadAnimationsTask = Task {
            await rebuildAnimationCacheAsync(deleteStaleEntries: deleteStaleEntries)
        }
    }

    // Async version that can be awaited for sequential execution
    private static func rebuildPlaylistCacheAsync(deleteStaleEntries: Bool = false) async {
        logger.debug("calling out to the server now...")
        let server = CreatureServerClient.shared
        let result = await server.getAllPlaylists()
        switch result {
        case .success(let playlists):
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = PlaylistImporter(modelContainer: container)

                // Optionally delete entries not in the server response
                if deleteStaleEntries {
                    let ids = Set(playlists.map { $0.id })
                    try await importer.deleteAllExcept(ids: ids)
                    logger.debug("deleted stale playlist entries not in server response")
                }

                try await importer.upsertBatch(playlists)
                logger.info(
                    "(re)built the playlist cache in SwiftData: imported \(playlists.count) playlists"
                )
            } catch {
                logger.warning(
                    "unable to import playlists into SwiftData: \(error.localizedDescription)")
                await AppState.shared.setSystemAlert(
                    show: true,
                    message:
                        "Unable to reload the playlist cache after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            logger.warning(
                "unable to fetch playlists from server: \(error.localizedDescription)")
            await AppState.shared.setSystemAlert(
                show: true,
                message:
                    "Unable to fetch playlists after invalidation: \(error.localizedDescription)"
            )
        }
    }

    static func rebuildPlaylistCache(deleteStaleEntries: Bool = false) {
        logger.info("attempting to rebuild the playlist cache (SwiftData import)")

        loadPlaylistsTask?.cancel()

        loadPlaylistsTask = Task {
            await rebuildPlaylistCacheAsync(deleteStaleEntries: deleteStaleEntries)
        }
    }


    // Async version that can be awaited for sequential execution
    private static func rebuildSoundListCacheAsync(deleteStaleEntries: Bool = false) async {
        logger.debug("calling out to the server now...")
        let server = CreatureServerClient.shared
        let result = await server.listSounds()
        switch result {
        case .success(let sounds):
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = SoundImporter(modelContainer: container)

                // Optionally delete entries not in the server response
                if deleteStaleEntries {
                    let ids = Set(sounds.map { $0.id })
                    try await importer.deleteAllExcept(ids: ids)
                    logger.debug("deleted stale sound entries not in server response")
                }

                try await importer.upsertBatch(sounds)
                logger.info(
                    "(re)built the sound list in SwiftData: imported \(sounds.count) sounds")
            } catch {
                logger.warning(
                    "unable to import sounds into SwiftData: \(error.localizedDescription)")
                await AppState.shared.setSystemAlert(
                    show: true,
                    message:
                        "Unable to reload the sound list after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            logger.warning("unable to fetch sounds from server: \(error.localizedDescription)")
            await AppState.shared.setSystemAlert(
                show: true,
                message:
                    "Unable to fetch sounds after invalidation: \(error.localizedDescription)"
            )
        }
    }

    static func rebuildSoundListCache(deleteStaleEntries: Bool = false) {
        logger.info("attempting to rebuild the sound list (SwiftData import)")

        loadSoundListsTask?.cancel()

        loadSoundListsTask = Task {
            await rebuildSoundListCacheAsync(deleteStaleEntries: deleteStaleEntries)
        }
    }

    static func rebuildAllCaches() {
        logger.info("rebuilding all SwiftData caches (with stale entry deletion)")

        // Run cache rebuilds sequentially to avoid concurrent SwiftData access
        // Each rebuild creates a Task that performs async database operations,
        // so running them in parallel causes race conditions and crashes
        Task {
            // Cancel any existing rebuild tasks first
            loadCeaturesTask?.cancel()
            loadAnimationsTask?.cancel()
            loadPlaylistsTask?.cancel()
            loadSoundListsTask?.cancel()

            // Run rebuilds one at a time
            await rebuildCreatureCacheAsync(deleteStaleEntries: true)
            await rebuildAnimationCacheAsync(deleteStaleEntries: true)
            await rebuildPlaylistCacheAsync(deleteStaleEntries: true)
            await rebuildSoundListCacheAsync(deleteStaleEntries: true)

            logger.info("completed rebuild of all caches with stale entry deletion")
        }
    }
}
