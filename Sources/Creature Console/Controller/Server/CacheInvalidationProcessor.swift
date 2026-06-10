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
    static nonisolated(unsafe) private var loadFixturesTask: Task<Void, Never>? = nil
    static nonisolated(unsafe) private var loadDialogScriptsTask: Task<Void, Never>? = nil
    static nonisolated(unsafe) private var loadStoryboardsTask: Task<Void, Never>? = nil


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
        case .fixture:
            rebuildFixtureCache(deleteStaleEntries: true)
        case .dialogScriptList:
            rebuildDialogScriptCache(deleteStaleEntries: true)
        case .storyboardList:
            rebuildStoryboardCache(deleteStaleEntries: true)
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


    // Async version that can be awaited for sequential execution
    private static func rebuildFixtureCacheAsync(deleteStaleEntries: Bool = false) async {
        logger.debug("calling out to the server now...")
        let server = CreatureServerClient.shared
        let result = await server.getAllFixtures()
        switch result {
        case .success(let fixtures):
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = DmxFixtureImporter(modelContainer: container)

                if deleteStaleEntries {
                    let ids = Set(fixtures.map { $0.id })
                    try await importer.deleteAllExcept(ids: ids)
                    logger.debug("deleted stale fixture entries not in server response")
                }

                try await importer.upsertBatch(fixtures)
                logger.info(
                    "(re)built the fixture cache in SwiftData: imported \(fixtures.count) fixtures"
                )
            } catch {
                logger.warning(
                    "unable to import fixtures into SwiftData: \(error.localizedDescription)")
                await AppState.shared.setSystemAlert(
                    show: true,
                    message:
                        "Unable to reload the fixture cache after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            logger.warning(
                "unable to fetch fixtures from server: \(error.localizedDescription)")
            await AppState.shared.setSystemAlert(
                show: true,
                message:
                    "Unable to fetch fixtures after invalidation: \(error.localizedDescription)"
            )
        }
    }

    static func rebuildFixtureCache(deleteStaleEntries: Bool = false) {
        logger.info("attempting to rebuild the fixture cache (SwiftData import)")

        loadFixturesTask?.cancel()

        loadFixturesTask = Task {
            await rebuildFixtureCacheAsync(deleteStaleEntries: deleteStaleEntries)
        }
    }

    // Async version that can be awaited for sequential execution
    private static func rebuildDialogScriptCacheAsync(deleteStaleEntries: Bool = false) async {
        logger.debug("calling out to the server now...")
        let server = CreatureServerClient.shared
        let result = await server.listDialogScripts()
        switch result {
        case .success(let scripts):
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = DialogScriptImporter(modelContainer: container)

                if deleteStaleEntries {
                    let ids = Set(scripts.map { $0.id })
                    try await importer.deleteAllExcept(ids: ids)
                    logger.debug("deleted stale dialog script entries not in server response")
                }

                try await importer.upsertBatch(scripts)
                logger.info(
                    "(re)built the dialog script cache in SwiftData: imported \(scripts.count) scripts"
                )
            } catch {
                logger.warning(
                    "unable to import dialog scripts into SwiftData: \(error.localizedDescription)")
                await AppState.shared.setSystemAlert(
                    show: true,
                    message:
                        "Unable to reload the dialog script cache after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            logger.warning(
                "unable to fetch dialog scripts from server: \(error.localizedDescription)")
            await AppState.shared.setSystemAlert(
                show: true,
                message:
                    "Unable to fetch dialog scripts after invalidation: \(error.localizedDescription)"
            )
        }
    }

    static func rebuildDialogScriptCache(deleteStaleEntries: Bool = false) {
        logger.info("attempting to rebuild the dialog script cache (SwiftData import)")

        loadDialogScriptsTask?.cancel()

        loadDialogScriptsTask = Task {
            await rebuildDialogScriptCacheAsync(deleteStaleEntries: deleteStaleEntries)
        }
    }

    // Async version that can be awaited for sequential execution
    private static func rebuildStoryboardCacheAsync(deleteStaleEntries: Bool = false) async {
        logger.debug("calling out to the server now...")
        let server = CreatureServerClient.shared
        let result = await server.listStoryboards()
        switch result {
        case .success(let storyboards):
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = StoryboardImporter(modelContainer: container)

                if deleteStaleEntries {
                    let ids = Set(storyboards.map { $0.id })
                    try await importer.deleteAllExcept(ids: ids)
                    logger.debug("deleted stale storyboard entries not in server response")
                }

                try await importer.upsertBatch(storyboards)
                logger.info(
                    "(re)built the storyboard cache in SwiftData: imported \(storyboards.count) storyboards"
                )
            } catch {
                logger.warning(
                    "unable to import storyboards into SwiftData: \(error.localizedDescription)")
                await AppState.shared.setSystemAlert(
                    show: true,
                    message:
                        "Unable to reload the storyboard cache after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            logger.warning(
                "unable to fetch storyboards from server: \(error.localizedDescription)")
            await AppState.shared.setSystemAlert(
                show: true,
                message:
                    "Unable to fetch storyboards after invalidation: \(error.localizedDescription)"
            )
        }
    }

    static func rebuildStoryboardCache(deleteStaleEntries: Bool = false) {
        logger.info("attempting to rebuild the storyboard cache (SwiftData import)")

        loadStoryboardsTask?.cancel()

        loadStoryboardsTask = Task {
            await rebuildStoryboardCacheAsync(deleteStaleEntries: deleteStaleEntries)
        }
    }

    static func rebuildAllCaches() {
        Task {
            await rebuildAllCachesAsync()
        }
    }

    // Awaitable variant so callers (like the Debug settings reset flow) can report
    // completion to the user.
    static func rebuildAllCachesAsync() async {
        logger.info("rebuilding all SwiftData caches (with stale entry deletion)")

        // Cancel any existing rebuild tasks first
        loadCeaturesTask?.cancel()
        loadAnimationsTask?.cancel()
        loadPlaylistsTask?.cancel()
        loadSoundListsTask?.cancel()
        loadFixturesTask?.cancel()
        loadDialogScriptsTask?.cancel()
        loadStoryboardsTask?.cancel()

        // Run cache rebuilds sequentially to avoid concurrent SwiftData access —
        // running them in parallel causes race conditions and crashes
        await rebuildCreatureCacheAsync(deleteStaleEntries: true)
        await rebuildAnimationCacheAsync(deleteStaleEntries: true)
        await rebuildPlaylistCacheAsync(deleteStaleEntries: true)
        await rebuildSoundListCacheAsync(deleteStaleEntries: true)
        await rebuildFixtureCacheAsync(deleteStaleEntries: true)
        await rebuildDialogScriptCacheAsync(deleteStaleEntries: true)
        await rebuildStoryboardCacheAsync(deleteStaleEntries: true)

        logger.info("completed rebuild of all caches with stale entry deletion")
    }

    /// Wipe every record from the local SwiftData store and pull a fresh copy of
    /// everything from the server. This is the heavy hammer for when the local cache
    /// has drifted from reality (e.g. items deleted on the server still showing up).
    static func resetLocalStoreAndResync() async throws {
        logger.info("resetting the local SwiftData store")

        let container = await SwiftDataStore.shared.container()
        let wiper = SwiftDataStoreWiper(modelContainer: container)
        try await wiper.wipeAll()
        logger.info("local SwiftData store wiped, re-syncing from the server")

        await rebuildAllCachesAsync()
    }
}
