import Common
import Foundation
import OSLog
import SwiftData

/// Rebuilds the local SwiftData caches when the server invalidates them (or the user asks).
///
/// An actor: invalidations arrive on the websocket pipeline and can overlap with user-triggered
/// rebuilds (Debug settings) and the cancel-everything path in `rebuildAll()`, so the per-cache
/// task handles need real isolation. Rebuilds of the *same* cache supersede each other; rebuilds
/// of different caches run independently.
actor CacheInvalidationProcessor {

    static let shared = CacheInvalidationProcessor()

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CacheInvalidationProcessor")

    /// The caches this processor knows how to rebuild, in the order `rebuildAll()` runs them.
    enum Cache: CaseIterable, Sendable {
        case creature
        case animation
        case playlist
        case soundList
        case fixture
        case dialogScript
        case storyboard

        var noun: String {
            switch self {
            case .creature: return "creature"
            case .animation: return "animation"
            case .playlist: return "playlist"
            case .soundList: return "sound list"
            case .fixture: return "fixture"
            case .dialogScript: return "dialog script"
            case .storyboard: return "storyboard"
            }
        }
    }

    private var rebuildTasks: [Cache: Task<Void, Never>] = [:]

    private init() {}


    // MARK: - Fire-and-forget conveniences for synchronous call sites

    static func process(_ request: CacheInvalidation) {
        Task { await shared.process(request) }
    }

    static func rebuild(_ cache: Cache, deleteStaleEntries: Bool = false) {
        Task { await shared.rebuild(cache, deleteStaleEntries: deleteStaleEntries) }
    }

    /// A permanent dialog render writes to both the animation and sound collections, so the
    /// render + re-render surfaces refresh both once the job completes (rather than waiting on
    /// the websocket invalidation). One call so those sites don't drift apart.
    static func rebuildAfterDialogRender() {
        rebuild(.animation, deleteStaleEntries: true)
        rebuild(.soundList, deleteStaleEntries: true)
    }

    static func rebuildAllCaches() {
        Task { await shared.rebuildAll() }
    }

    static func resetLocalStoreAndResync() async throws {
        try await shared.resetAndResync()
    }


    // MARK: - Actor-isolated implementation

    func process(_ request: CacheInvalidation) {
        switch request.cacheType {
        case .creature:
            rebuild(.creature, deleteStaleEntries: true)
        case .animation:
            rebuild(.animation, deleteStaleEntries: true)
        case .playlist:
            rebuild(.playlist, deleteStaleEntries: true)
        case .soundList:
            rebuild(.soundList, deleteStaleEntries: true)
        case .fixture:
            rebuild(.fixture, deleteStaleEntries: true)
        case .dialogScriptList:
            rebuild(.dialogScript, deleteStaleEntries: true)
        case .storyboardList:
            rebuild(.storyboard, deleteStaleEntries: true)
        case .adHocAnimationList:
            logger.info("ad-hoc animation cache invalidation received - refresh handler pending")
        case .adHocSoundList:
            logger.info("ad-hoc sound cache invalidation received - refresh handler pending")
        default:
            return
        }
    }

    func rebuild(_ cache: Cache, deleteStaleEntries: Bool = false) {
        logger.info("attempting to rebuild the \(cache.noun) cache (SwiftData import)")
        rebuildTasks[cache]?.cancel()
        rebuildTasks[cache] = Task {
            await self.rebuildNow(cache, deleteStaleEntries: deleteStaleEntries)
        }
    }

    /// Awaitable full rebuild so callers (like the Debug settings reset flow) can report
    /// completion to the user. Runs the caches **sequentially** — parallel rebuilds contend on
    /// SwiftData and have crashed in the past.
    func rebuildAll() async {
        logger.info("rebuilding all SwiftData caches (with stale entry deletion)")

        for task in rebuildTasks.values {
            task.cancel()
        }
        rebuildTasks.removeAll()

        for cache in Cache.allCases {
            await rebuildNow(cache, deleteStaleEntries: true)
        }

        logger.info("completed rebuild of all caches with stale entry deletion")
    }

    /// Wipe every record from the local SwiftData store and pull a fresh copy of
    /// everything from the server. This is the heavy hammer for when the local cache
    /// has drifted from reality (e.g. items deleted on the server still showing up).
    func resetAndResync() async throws {
        logger.info("resetting the local SwiftData store")

        let container = await SwiftDataStore.shared.container()
        let wiper = SwiftDataStoreWiper(modelContainer: container)
        try await wiper.wipeAll()
        logger.info("local SwiftData store wiped, re-syncing from the server")

        await rebuildAll()
    }


    // MARK: - The one sync pipeline every cache goes through

    private func rebuildNow(_ cache: Cache, deleteStaleEntries: Bool) async {
        let server = CreatureServerClient.shared
        let container = await SwiftDataStore.shared.container()

        switch cache {
        case .creature:
            let importer = CreatureImporter(modelContainer: container)
            await sync(
                cache, deleteStaleEntries, fetch: { await server.getAllCreatures() },
                ids: { Set($0.map(\.id)) },
                deleteAllExcept: importer.deleteAllExcept, upsert: importer.upsertBatch)
        case .animation:
            let importer = AnimationMetadataImporter(modelContainer: container)
            await sync(
                cache, deleteStaleEntries, fetch: { await server.listAnimations() },
                ids: { Set($0.map(\.id)) },
                deleteAllExcept: importer.deleteAllExcept, upsert: importer.upsertBatch)
        case .playlist:
            let importer = PlaylistImporter(modelContainer: container)
            await sync(
                cache, deleteStaleEntries, fetch: { await server.getAllPlaylists() },
                ids: { Set($0.map(\.id)) },
                deleteAllExcept: importer.deleteAllExcept, upsert: importer.upsertBatch)
        case .soundList:
            let importer = SoundImporter(modelContainer: container)
            await sync(
                cache, deleteStaleEntries, fetch: { await server.listSounds() },
                ids: { Set($0.map(\.id)) },
                deleteAllExcept: importer.deleteAllExcept, upsert: importer.upsertBatch)
        case .fixture:
            let importer = DmxFixtureImporter(modelContainer: container)
            await sync(
                cache, deleteStaleEntries, fetch: { await server.getAllFixtures() },
                ids: { Set($0.map(\.id)) },
                deleteAllExcept: importer.deleteAllExcept, upsert: importer.upsertBatch)
        case .dialogScript:
            let importer = DialogScriptImporter(modelContainer: container)
            await sync(
                cache, deleteStaleEntries, fetch: { await server.listDialogScripts() },
                ids: { Set($0.map(\.id)) },
                deleteAllExcept: importer.deleteAllExcept, upsert: importer.upsertBatch)
        case .storyboard:
            let importer = StoryboardImporter(modelContainer: container)
            await sync(
                cache, deleteStaleEntries, fetch: { await server.listStoryboards() },
                ids: { Set($0.map(\.id)) },
                deleteAllExcept: importer.deleteAllExcept, upsert: importer.upsertBatch)
        }
    }

    private func sync<Item: Sendable, ID: Hashable & Sendable>(
        _ cache: Cache,
        _ deleteStaleEntries: Bool,
        fetch: () async -> Result<[Item], ServerError>,
        ids: ([Item]) -> Set<ID>,
        deleteAllExcept: (Set<ID>) async throws -> Void,
        upsert: ([Item]) async throws -> Void
    ) async {
        logger.debug("fetching the \(cache.noun) list from the server...")

        switch await fetch() {
        case .success(let items):
            do {
                if deleteStaleEntries {
                    try await deleteAllExcept(ids(items))
                    logger.debug("deleted stale \(cache.noun) entries not in server response")
                }
                try await upsert(items)
                logger.info(
                    "(re)built the \(cache.noun) cache in SwiftData: imported \(items.count) items"
                )
            } catch {
                await reportFailure(
                    "Unable to reload the \(cache.noun) cache after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            await reportFailure(
                "Unable to fetch the \(cache.noun) list after invalidation: \(error.localizedDescription)"
            )
        }
    }

    private func reportFailure(_ message: String) async {
        logger.warning("\(message)")
        await AppState.shared.setSystemAlert(show: true, message: message)
    }
}
