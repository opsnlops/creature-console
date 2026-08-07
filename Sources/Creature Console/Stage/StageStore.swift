import Common
import Foundation
import OSLog
import Observation

/// Owns the set of stages on the server and whichever one is currently being edited.
///
/// ## Why edits aren't auto-saved
///
/// A stage's `updated_at` is what animation staleness is measured against — every animation
/// rendered against a stage becomes stale the moment that stage is saved. Writing on every
/// slider tick would invalidate the entire rendered catalogue continuously while someone is
/// just *looking* at the layout. So edits accumulate locally and the operator saves
/// deliberately.
///
/// For the same reason nothing here silently adds creatures to a stage: opening the view must
/// never dirty the document.
@MainActor
@Observable
final class StageStore {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var stages: [Stage] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isSaving = false
    private(set) var saveError: String?
    /// How many animations rendered against the selected stage are now out of date.
    private(set) var animationStaleness: StageAnimationsDTO?

    /// Progress of a batch re-render kicked off from the Dialogs section.
    struct RerenderRun: Equatable {
        var completed: Int
        var total: Int
        var currentTitle: String?
    }

    /// Non-nil while "Re-render All" is running.
    private(set) var rerenderRun: RerenderRun?
    /// Failures from the last batch re-render, if any.
    private(set) var rerenderNotice: String?

    /// Set when the stage being edited changed somewhere else while there are unsaved edits here.
    /// Nil whenever the working copy is clean — a clean stage just adopts the incoming version.
    private(set) var remoteChangeNotice: String?

    /// The version that arrived from elsewhere, held until the operator chooses to take it.
    @ObservationIgnored private var pendingRemoteStage: Stage?

    /// The stage being edited, including unsaved changes.
    var stage: Stage? {
        didSet {
            guard let stage else { return }
            onStageChanged?(stage)
        }
    }

    /// The last version the server confirmed, used to tell edited from untouched.
    private(set) var savedStage: Stage?

    /// Called whenever the working stage changes so the renderer can follow along live — the
    /// operator should hear a move while dragging, even though nothing is persisted yet.
    @ObservationIgnored var onStageChanged: ((Stage) -> Void)?

    @ObservationIgnored private var knownCreatures: [StageCreature] = []
    @ObservationIgnored private let server: CreatureServerClient
    @ObservationIgnored private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "StageStore")

    init(server: CreatureServerClient = .shared) {
        self.server = server
    }

    var hasUnsavedChanges: Bool {
        guard let stage, let savedStage else { return false }
        return stage != savedStage
    }

    var validationProblem: String? {
        stage?.validationProblem
    }

    var canSave: Bool {
        hasUnsavedChanges && validationProblem == nil && !isSaving
    }

    // MARK: - Loading

    func load(selecting preferredID: StageIdentifier? = nil) async {
        loadState = .loading
        switch await server.listStages() {
        case .success(let loaded):
            stages = loaded
            loadState = .loaded
            if let migrated = await migrateLegacyLayoutIfNeeded() {
                select(migrated.id)
                return
            }
            let target =
                preferredID ?? stage?.id ?? Self.lastSelectedStageID() ?? loaded.first?.id
            select(target)
            // Seed the SwiftData mirror. This costs a second fetch on open, but the mirror is what
            // carries changes from other devices, and on a cold store (or right after a schema
            // wipe) nothing else would populate it — leaving the live-update path silently dead.
            CacheInvalidationProcessor.rebuild(.stage, deleteStaleEntries: true)
        case .failure(let error):
            let message = ServerError.detailedMessage(from: error)
            logger.warning("Could not load stages: \(message)")
            loadState = .failed(message)
        }
    }

    func select(_ id: StageIdentifier?) {
        guard let id, let match = stages.first(where: { $0.id == id }) else {
            stage = nil
            savedStage = nil
            animationStaleness = nil
            remoteChangeNotice = nil
            pendingRemoteStage = nil
            return
        }
        stage = match
        savedStage = match
        animationStaleness = nil
        remoteChangeNotice = nil
        pendingRemoteStage = nil
        Self.rememberSelectedStageID(id)
        Task { await refreshStaleness(for: id) }
    }

    /// Re-render every stale animation on this stage, one at a time.
    ///
    /// Each item becomes a render request pinned to **this stage explicitly** — not the script's
    /// current binding, which may have moved on. A stale mainstage rendition should come back as
    /// a mainstage rendition even if its script now points at the travel stage. No generation id
    /// is sent, so the server reuses the cached voice take: a stage move changes where heads
    /// point, not what anyone says, and re-spending ElevenLabs on it would be pure waste.
    ///
    /// Sequential on purpose: renders contend for the same audio pipeline server-side, and
    /// "Re-rendering 2 of 3" is legible in a way six interleaved progress bars are not.
    func rerenderStaleAnimations() async {
        guard rerenderRun == nil, let stageID = stage?.id else { return }
        let stale = animationStaleness?.items.filter(\.isStale) ?? []
        guard !stale.isEmpty else { return }

        rerenderNotice = nil
        rerenderRun = RerenderRun(completed: 0, total: stale.count, currentTitle: nil)
        var failures: [String] = []

        for (index, item) in stale.enumerated() {
            rerenderRun = RerenderRun(
                completed: index, total: stale.count, currentTitle: item.title)

            guard let scriptID = UUID(uuidString: item.sourceScriptID) else {
                failures.append("\(item.title): source script id isn't a UUID")
                continue
            }

            let request = DialogRequest.fromScript(
                scriptID, persistence: .permanent, title: item.title, stageId: stageID)

            switch await server.renderDialog(request) {
            case .success(let job):
                await JobStatusStore.shared.seedQueued(job)
                for await event in await JobStatusStore.shared.events(forJob: job.jobId) {
                    if case .terminal(let info) = event {
                        if info.status == .failed {
                            failures.append(item.title + ": " + (info.result ?? "render failed"))
                        }
                        break
                    }
                }
            case .failure(let error):
                failures.append(item.title + ": " + ServerError.detailedMessage(from: error))
            }
        }

        rerenderRun = nil
        if !failures.isEmpty {
            rerenderNotice = "Some re-renders failed — " + failures.joined(separator: "; ")
        }
        await refreshStaleness(for: stageID)
    }

    /// Ask the server how much of the rendered catalogue this stage has outdated.
    func refreshStaleness(for id: StageIdentifier) async {
        switch await server.listStageAnimations(id: id) {
        case .success(let report):
            // Only apply if the operator hasn't moved on to another stage meanwhile.
            guard stage?.id == id else { return }
            animationStaleness = report
        case .failure(let error):
            logger.debug(
                "Could not load stage animation staleness: \(ServerError.detailedMessage(from: error))"
            )
        }
    }

    /// Throw away local edits and go back to what the server last confirmed.
    ///
    /// If another device changed this stage while it was being edited, reverting takes *that*
    /// version — discarding local edits to go back to a copy known to be stale would be a strange
    /// thing to offer.
    func revert() {
        saveError = nil
        if let pending = pendingRemoteStage {
            adopt(pending)
            return
        }
        stage = savedStage
    }

    // MARK: - Changes from elsewhere

    /// Take the freshest list from the local SwiftData mirror, which the `stage-list` cache
    /// invalidation keeps current across devices.
    ///
    /// The list itself is always safe to replace. The *working copy* is not: if this device has
    /// unsaved edits, silently re-reading the document would throw away whatever was mid-drag —
    /// worse than the stale display it fixes. So a clean stage adopts the incoming version, and a
    /// dirty one keeps its edits and says the stage moved underneath it.
    func syncStages(from incoming: [Stage]) {
        stages = incoming
        if loadState == .idle { loadState = .loaded }

        guard let current = stage else { return }

        guard let match = incoming.first(where: { $0.id == current.id }) else {
            // Deleted elsewhere. Unsaved work is still worth more than a tidy picker, so it stays
            // put and says so rather than vanishing mid-edit.
            if hasUnsavedChanges {
                remoteChangeNotice = "This stage was deleted on another device."
                pendingRemoteStage = nil
            } else {
                select(incoming.first?.id)
            }
            return
        }

        // Unchanged since we last saw it — including our own save echoing back through the cache.
        guard match != savedStage else { return }

        if hasUnsavedChanges {
            pendingRemoteStage = match
            remoteChangeNotice =
                "This stage changed on another device. Reverting will take their version and discard your unsaved edits."
        } else {
            adopt(match)
        }
    }

    /// Replace the working copy with a version from elsewhere.
    private func adopt(_ incoming: Stage) {
        stage = incoming
        savedStage = incoming
        pendingRemoteStage = nil
        remoteChangeNotice = nil
        Task { await refreshStaleness(for: incoming.id) }
    }

    // MARK: - Saving

    func save() async {
        guard let edited = stage, hasUnsavedChanges else { return }
        let working = refreshedCachedNames(in: edited)
        if let problem = working.validationProblem {
            saveError = problem
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        switch await server.updateStage(working) {
        case .success(let saved):
            apply(saved)
            CacheInvalidationProcessor.rebuild(.stage, deleteStaleEntries: true)
            // The save just bumped updated_at, so everything rendered against this stage is
            // now stale — re-read rather than showing the pre-save count.
            await refreshStaleness(for: saved.id)
        case .failure(let error):
            let message = ServerError.detailedMessage(from: error)
            logger.warning("Could not save stage \(working.id): \(message)")
            saveError = message
        }
    }

    func create(title: String) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        switch await server.createStage(Stage(id: UUID(), title: title)) {
        case .success(let created):
            stages.insert(created, at: 0)
            select(created.id)
            CacheInvalidationProcessor.rebuild(.stage, deleteStaleEntries: true)
        case .failure(let error):
            saveError = ServerError.detailedMessage(from: error)
        }
    }

    func rename(to title: String) async {
        guard var working = stage else { return }
        working.title = title
        stage = working
        await save()
    }

    func delete(id: StageIdentifier) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        switch await server.deleteStage(id: id) {
        case .success:
            stages.removeAll { $0.id == id }
            if stage?.id == id {
                select(stages.first?.id)
            }
            CacheInvalidationProcessor.rebuild(.stage, deleteStaleEntries: true)
        case .failure(let error):
            saveError = ServerError.detailedMessage(from: error)
        }
    }

    // MARK: - Editing

    /// Mutate one placement in the working copy. Nothing is sent to the server.
    func updatePlacement(
        creatureID: CreatureIdentifier,
        _ update: (inout StagePlacement) -> Void
    ) {
        guard var working = stage,
            let index = working.placements.firstIndex(where: { $0.creatureID == creatureID })
        else {
            return
        }
        update(&working.placements[index])
        // Yaw is normalized on the way in so the editor and the server's gaze layer can't
        // disagree about which way a creature is pointed.
        working.placements[index].yaw = StagePlacement.normalizedYaw(
            working.placements[index].yaw)
        stage = working
    }

    func addCreature(_ creature: StageCreature) {
        guard var working = stage else { return }
        guard working.placement(for: creature.id) == nil else { return }
        guard working.placements.count < StageLimits.maxPlacements else {
            saveError =
                "This stage already has \(StageLimits.maxPlacements) creatures, one per audio lane."
            return
        }
        // Drop them in front of the listener, facing back at them, rather than at the origin —
        // the origin is inside the listener's head.
        let position = (x: Float(0), y: Float(0), z: Float(-3))
        working.placements.append(
            StagePlacement(
                creatureID: creature.id,
                creatureName: creature.name,
                audioChannel: creature.audioChannel,
                x: position.x,
                y: position.y,
                z: position.z,
                yaw: StageFrame.headingTowardListener(from: position)))
        stage = working
    }

    func removeCreature(id: CreatureIdentifier) {
        guard var working = stage else { return }
        working.placements.removeAll { $0.creatureID == id }
        stage = working
    }

    /// Note the current creature list so cached display names can be refreshed on the next
    /// save.
    ///
    /// Deliberately does **not** touch the working stage. A placement's `creatureName` is only
    /// a cache for rendering, and rewriting it here would mark the document dirty — and
    /// therefore every animation rendered against it stale — just because somebody opened the
    /// view after a creature was renamed. Callers display the live name and fall back to the
    /// cached one; the document catches up whenever it's next saved for a real reason.
    func noteKnownCreatures(_ creatures: [StageCreature]) {
        knownCreatures = creatures
    }

    /// Bring cached display names in line with the creature list. Called as part of an
    /// operator-initiated save, never on its own.
    private func refreshedCachedNames(in stage: Stage) -> Stage {
        guard !knownCreatures.isEmpty else { return stage }
        var updated = stage
        let byID = Dictionary(uniqueKeysWithValues: knownCreatures.map { ($0.id, $0) })
        for index in updated.placements.indices {
            guard let creature = byID[updated.placements[index].creatureID] else { continue }
            updated.placements[index].creatureName = creature.name
        }
        return updated
    }

    // MARK: - Migration

    /// Hand this Mac's pre-#67 `UserDefaults` layout to the server, once.
    ///
    /// Only runs when the server has no stages at all. If stages already exist, someone has
    /// authored one — importing a stale local copy alongside it would be two documents again,
    /// which is the thing this whole change exists to stop.
    ///
    /// macOS-only by construction: the spatial renderer that wrote that layout never shipped
    /// anywhere else, so there is nothing to migrate on iOS.
    private func migrateLegacyLayoutIfNeeded() async -> Stage? {
        #if os(macOS)
            guard stages.isEmpty else {
                // Nothing to do, but don't try again on every load.
                SpatialStageMigration.markMigrated()
                return nil
            }
            guard let legacy = SpatialStageMigration.pendingLegacyLayout(),
                !legacy.placements.isEmpty
            else {
                return nil
            }

            let candidate = SpatialStageMigration.stage(from: legacy)
            logger.info(
                "Migrating a local stage layout with \(legacy.placements.count) placement(s) to the server"
            )
            switch await server.createStage(candidate) {
            case .success(let created):
                SpatialStageMigration.markMigrated()
                stages.insert(created, at: 0)
                return created
            case .failure(let error):
                // Leave the flag unset so this is retried; the local layout is still readable.
                logger.warning(
                    "Could not migrate the local stage layout: \(ServerError.detailedMessage(from: error))"
                )
                saveError =
                    "Couldn't move this Mac's saved layout to the server: "
                    + ServerError.detailedMessage(from: error)
                return nil
            }
        #else
            return nil
        #endif
    }

    // MARK: - Helpers

    private func apply(_ saved: Stage) {
        if let index = stages.firstIndex(where: { $0.id == saved.id }) {
            stages[index] = saved
        } else {
            stages.insert(saved, at: 0)
        }
        stage = saved
        savedStage = saved
    }

    private static let selectedStageDefaultsKey = "spatialStage.selectedStageID"

    private static func lastSelectedStageID() -> StageIdentifier? {
        guard let raw = UserDefaults.standard.string(forKey: selectedStageDefaultsKey) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private static func rememberSelectedStageID(_ id: StageIdentifier) {
        UserDefaults.standard.set(id.uuidString, forKey: selectedStageDefaultsKey)
    }
}
