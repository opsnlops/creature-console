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

        logger.info("attempting to rebuild the creature cache (SwiftData import)")

        loadCeaturesTask?.cancel()

        loadCeaturesTask = Task {
            logger.debug("calling out to the server now...")
            let server = CreatureServerClient.shared
            let result = await server.getAllCreatures()
            switch result {
            case .success(let creatures):
                do {
                    let container = await SwiftDataStore.shared.container()
                    let importer = CreatureImporter(modelContainer: container)
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

    }

    static func rebuildAnimationCache() {

        logger.info("attempting to rebuild the animation cache (SwiftData import)")

        loadAnimationsTask?.cancel()

        loadAnimationsTask = Task {
            logger.debug("calling out to the server now...")
            let server = CreatureServerClient.shared
            let result = await server.listAnimations()
            switch result {
            case .success(let animations):
                do {
                    let container = await SwiftDataStore.shared.container()
                    let importer = AnimationMetadataImporter(modelContainer: container)
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

    }

    static func rebuildPlaylistCache() {

        logger.info("attempting to rebuild the playlist cache (SwiftData import)")

        loadPlaylistsTask?.cancel()

        loadPlaylistsTask = Task {
            logger.debug("calling out to the server now...")
            let server = CreatureServerClient.shared
            let result = await server.getAllPlaylists()
            switch result {
            case .success(let playlists):
                do {
                    let container = await SwiftDataStore.shared.container()
                    let importer = PlaylistImporter(modelContainer: container)
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

    }


    static func rebuildSoundListCache() {

        logger.info("attempting to rebuild the sound list (SwiftData import)")

        loadSoundListsTask?.cancel()

        loadSoundListsTask = Task {
            logger.debug("calling out to the server now...")
            let server = CreatureServerClient.shared
            let result = await server.listSounds()
            switch result {
            case .success(let sounds):
                do {
                    let container = await SwiftDataStore.shared.container()
                    let importer = SoundImporter(modelContainer: container)
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

    }
}
