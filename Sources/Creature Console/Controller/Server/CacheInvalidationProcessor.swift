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
        logger.info("received server cache invalidation: \(request.cacheType.rawValue)")
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
            refreshDialogScriptsByKnownIDs()
        case .storyboardList:
            rebuild(.storyboard, deleteStaleEntries: true)
        case .stageList:
            // Stages have no SwiftData cache yet; the stage store reads the server directly.
            logger.info("stage cache invalidation received - local stage cache pending")
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

    /// Refresh saved scripts through the parameterized endpoint. The websocket invalidation only
    /// says that the script collection changed; it does not carry a script id, and the deployed
    /// server intentionally rejects the old collection GET. The local cache is our source of
    /// known ids, while successful create/update responses already upsert their canonical script.
    private func refreshDialogScriptsByKnownIDs() {
        logger.info("refreshing dialog scripts by their locally known ids")
        rebuildTasks[.dialogScript]?.cancel()
        rebuildTasks[.dialogScript] = Task {
            let server = CreatureServerClient.shared
            let container = await SwiftDataStore.shared.container()
            let importer = DialogScriptImporter(modelContainer: container)

            do {
                let ids = try await importer.allIDs()
                guard !ids.isEmpty else {
                    logger.debug("dialog-script invalidation has no locally known ids")
                    return
                }

                var refreshed: [DialogScript] = []
                var deletedIDs: [DialogScriptIdentifier] = []
                var failures: [String] = []
                for id in ids {
                    guard !Task.isCancelled else { return }
                    switch await server.getDialogScript(id: id) {
                    case .success(let script):
                        refreshed.append(script)
                    case .failure(.notFound):
                        deletedIDs.append(id)
                    case .failure(let error):
                        failures.append(
                            "\(id.uuidString.lowercased()): \(error.localizedDescription)")
                    }
                }

                try await importer.upsertBatch(refreshed)
                for id in deletedIDs {
                    try await importer.delete(id: id)
                }
                logger.info(
                    "refreshed \(refreshed.count) dialog scripts by id; removed \(deletedIDs.count) stale entries"
                )
                if let failure = failures.first {
                    await reportFailure(
                        "Unable to refresh one or more dialog scripts after invalidation: \(failure)"
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await reportFailure(
                    "Unable to refresh dialog scripts after invalidation: \(error.localizedDescription)"
                )
            }
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
                // A newer invalidation intentionally supersedes this rebuild. URLSession reports
                // that cancellation as a communication error, but it is not actionable and must
                // not surface as an operational warning.
                guard !Task.isCancelled else { return }
                await reportFailure(
                    "Unable to reload the \(cache.noun) cache after getting an invalidation message: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            guard !Task.isCancelled else { return }
            await reportFailure(fetchFailureMessage(for: cache, error: error))
        }
    }

    private func fetchFailureMessage(for cache: Cache, error: ServerError) -> String {
        switch cache {
        case .soundList:
            return
                "The legacy sound-library refresh failed in the background; your current work can continue. "
                + "Details: \(error.localizedDescription)"
        default:
            return
                "Unable to fetch the \(cache.noun) data after invalidation: \(error.localizedDescription)"
        }
    }

    private func reportFailure(_ message: String) async {
        logger.warning("\(message)")
        await AppState.shared.postNotice(message)
    }
}
