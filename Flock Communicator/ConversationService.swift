import CreatureAppSupport
import Foundation
import SwiftData
import WorldCore

/// The part of the conversation on screen.
struct ConversationWindow: Equatable, Sendable {
    var items: [ConversationItem] = []
    /// The date of the oldest cached row in the window. It comes from the stored column rather
    /// than from `items`, which may lead with an unsent turn.
    var start: Date?
    /// Whether scrolling up can find anything: cached rows above the window, or unfetched history.
    var hasOlder = false
    /// Taken when the read began. A later revision never gives way to an earlier one.
    var revision = 0
}

/// How far this device's cache reaches. The cache is one unbroken run from `oldestItemID` to
/// `newestItemID`, plus any turns this device has sent since. A row existing proves nothing about
/// the rows around it, which is why this is stored rather than inferred from the cache.
struct ConversationSyncState: Equatable, Sendable {
    var newestItemID: ConversationItemID?
    var oldestItemID: ConversationItemID?
    var reachedBeginning: Bool
}

enum ConversationPaging {
    /// One page from the World, and the rows a window holds before anyone scrolls up.
    static let pageSize = 200
}

protocol CommunicatorConversationService: Sendable {
    /// Catches up with the World, then reads the window.
    func conversation() async throws -> ConversationWindow
    /// Reads the window without touching the network.
    func cachedConversation() async throws -> ConversationWindow
    /// Moves the window up a page, fetching from the World when the cache runs out.
    func olderConversation() async throws -> ConversationWindow
    func submit(text: String, inReplyTo item: ConversationItem?) async throws
    func updates() async throws -> WorldConversationUpdateStream
}

protocol CommunicatorWorldClient: Sendable {
    func submit(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult
    func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage
    func history(
        in conversationID: ConversationID,
        before itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage
    func updates(in conversationID: ConversationID) throws -> WorldConversationUpdateStream
}

extension WorldConversationClient: CommunicatorWorldClient {}

extension CommunicatorWorldClient {
    func updates(in conversationID: ConversationID) throws -> WorldConversationUpdateStream {
        WorldConversationUpdateStream { $0.finish() }
    }
}

extension CommunicatorConversationService {
    func updates() async throws -> WorldConversationUpdateStream {
        WorldConversationUpdateStream { $0.finish() }
    }
}

protocol CommunicatorWorldClientProviding: Sendable {
    func serverURI() async -> String
    func client() async throws -> any CommunicatorWorldClient
}

extension CommunicatorWorldClientProviding {
    func serverURI() async -> String { "test://world" }
}

protocol ConversationPersistence: Sendable {
    /// Rows from `start` onward, or the newest `limit` rows when there is no start. Unsent turns
    /// always come too.
    func conversationWindow(
        serverURI: String,
        from start: Date?,
        newest limit: Int
    ) async throws -> ConversationWindow
    /// Where a window would start to take in `count` more cached rows older than `date`, and how
    /// many it would find.
    func windowStart(
        serverURI: String,
        before date: Date,
        count: Int
    ) async throws -> (start: Date?, found: Int)
    func syncState(serverURI: String) async throws -> ConversationSyncState?
    func pendingUtterances(serverURI: String) async throws -> [PersonUtterance]
    func enqueue(
        _ utterance: PersonUtterance,
        inReplyTo itemID: ConversationItemID?,
        serverURI: String
    ) async throws
    func accept(_ result: UtteranceIngressResult, serverURI: String) async throws
    /// Replaces the server's cached rows with its newest page, and starts the cache's promise.
    func startHistory(
        with page: ConversationItemPage,
        serverURI: String
    ) async throws -> ConversationSyncState
    /// Caches a page read forward and advances `newestItemID` past it, together.
    func cacheNewer(_ items: [ConversationItem], serverURI: String) async throws
    /// Caches the page read backward from `anchor` and moves `oldestItemID` down to it, together.
    /// The page is dropped if the cache no longer starts at `anchor`.
    func cacheOlder(
        _ page: ConversationItemPage,
        before anchor: ConversationItemID?,
        serverURI: String
    ) async throws
}

actor LiveCommunicatorConversationService: CommunicatorConversationService {
    private let persistence: any ConversationPersistence
    private let clientProvider: any CommunicatorWorldClientProviding
    /// Set once someone scrolls up; until then the window is simply the newest rows.
    private var windowStarts: [String: Date] = [:]
    private var lastRevision = 0

    init(
        persistence: any ConversationPersistence,
        clientProvider: any CommunicatorWorldClientProviding
    ) {
        self.persistence = persistence
        self.clientProvider = clientProvider
    }

    func conversation() async throws -> ConversationWindow {
        let serverURI = await clientProvider.serverURI()
        await synchronizeBestEffort(serverURI: serverURI)
        return try await window(serverURI: serverURI)
    }

    func cachedConversation() async throws -> ConversationWindow {
        try await window(serverURI: clientProvider.serverURI())
    }

    func olderConversation() async throws -> ConversationWindow {
        let serverURI = await clientProvider.serverURI()
        var start = windowStarts[serverURI]
        if start == nil {
            start = try await window(serverURI: serverURI).start
        }
        guard let shownStart = start else { return try await window(serverURI: serverURI) }
        var older = try await persistence.windowStart(
            serverURI: serverURI,
            before: shownStart,
            count: ConversationPaging.pageSize
        )
        if older.found < ConversationPaging.pageSize {
            do {
                try await fetchOlderPage(serverURI: serverURI)
            } catch  where older.found > 0 {
                // What the cache still holds is worth showing; scrolling further will try again.
            }
            older = try await persistence.windowStart(
                serverURI: serverURI,
                before: shownStart,
                count: ConversationPaging.pageSize
            )
        }
        // Pinning the start even when nothing older was found brings in any rows that share the
        // oldest row's date, which a window of the newest rows can split.
        windowStarts[serverURI] = older.start ?? shownStart
        return try await window(serverURI: serverURI)
    }

    func submit(text: String, inReplyTo item: ConversationItem?) async throws {
        let utterance = try PersonUtterance(
            conversationID: ConversationIdentity.conversationID,
            speakerID: ConversationIdentity.aprilID,
            addresseeIDs: [ConversationIdentity.beakyID],
            inResponseToResponseID: item?.responseID,
            text: text,
            modality: .typed,
            source: item == nil ? .communicatorComposition : .communicatorReply,
            sourceID: ConversationIdentity.sourceID,
            occurredAt: Date(),
            confidence: 1
        )
        let serverURI = await clientProvider.serverURI()
        try await persistence.enqueue(
            utterance,
            inReplyTo: item?.itemID,
            serverURI: serverURI
        )
        await synchronizeBestEffort(serverURI: serverURI)
    }

    func updates() async throws -> WorldConversationUpdateStream {
        let client = try await clientProvider.client()
        return try client.updates(in: ConversationIdentity.conversationID)
    }

    private func window(serverURI: String) async throws -> ConversationWindow {
        lastRevision += 1
        let revision = lastRevision
        var window = try await persistence.conversationWindow(
            serverURI: serverURI,
            from: windowStarts[serverURI],
            newest: ConversationPaging.pageSize
        )
        window.revision = revision
        return window
    }

    private func synchronizeBestEffort(serverURI: String) async {
        do {
            // Read the position before flushing the outbox. A remote turn may have arrived while
            // this client was offline, and a flushed turn lands in the cache past it. The position
            // doesn't move for that turn, so catching up still finds the remote one.
            let saved = try await persistence.syncState(serverURI: serverURI)
            if saved == nil {
                // Nothing has synchronized, or the cache was cleared under this window.
                windowStarts[serverURI] = nil
            }
            let client = try await clientProvider.client()
            for utterance in try await persistence.pendingUtterances(serverURI: serverURI) {
                try await persistence.accept(
                    client.submit(utterance),
                    serverURI: serverURI
                )
            }
            if let saved {
                do {
                    try await catchUp(
                        using: client, after: saved.newestItemID, serverURI: serverURI)
                } catch  where Self.isRejectedCursor(error) {
                    try await startOver(using: client, serverURI: serverURI)
                }
            } else {
                try await startOver(using: client, serverURI: serverURI)
            }
        } catch {
            // The durable outbox and local cache remain available until the next synchronization.
        }
    }

    /// Takes the newest page as a fresh start, then reads forward past it.
    private func startOver(
        using client: any CommunicatorWorldClient,
        serverURI: String
    ) async throws {
        windowStarts[serverURI] = nil
        let page = try await client.history(
            in: ConversationIdentity.conversationID,
            before: nil,
            limit: ConversationPaging.pageSize
        )
        let state = try await persistence.startHistory(with: page, serverURI: serverURI)
        try await catchUp(using: client, after: state.newestItemID, serverURI: serverURI)
    }

    private func catchUp(
        using client: any CommunicatorWorldClient,
        after initialCursor: ConversationItemID?,
        serverURI: String
    ) async throws {
        var cursor = initialCursor
        repeat {
            let page = try await client.items(
                in: ConversationIdentity.conversationID,
                after: cursor,
                limit: ConversationPaging.pageSize
            )
            try await persistence.cacheNewer(page.items, serverURI: serverURI)
            guard page.hasMore else { break }
            guard let next = page.nextItemID, next != cursor else {
                throw ConversationSynchronizationError.invalidPaginationCursor
            }
            cursor = next
        } while true
    }

    private func fetchOlderPage(serverURI: String) async throws {
        guard let state = try await persistence.syncState(serverURI: serverURI),
            !state.reachedBeginning
        else { return }
        let client = try await clientProvider.client()
        do {
            let page = try await client.history(
                in: ConversationIdentity.conversationID,
                before: state.oldestItemID,
                limit: ConversationPaging.pageSize
            )
            try await persistence.cacheOlder(
                page,
                before: state.oldestItemID,
                serverURI: serverURI
            )
        } catch  where Self.isRejectedCursor(error) {
            try await startOver(using: client, serverURI: serverURI)
        }
    }

    /// The canonical history was replaced under this cursor. Anything else, such as the network
    /// going away, leaves the position good, and the next synchronization tries it again.
    private static func isRejectedCursor(_ error: any Error) -> Bool {
        switch error {
        case ConversationSynchronizationError.invalidPaginationCursor,
            WorldConversationClientError.requestFailed(statusCode: 400):
            true
        default:
            false
        }
    }
}

private enum ConversationSynchronizationError: Error {
    case invalidPaginationCursor
}

extension Notification.Name {
    static let communicatorConversationCacheCleared = Notification.Name(
        "communicatorConversationCacheCleared"
    )
}

@MainActor
enum ConversationCacheMaintenance {
    static func clear(using modelContext: ModelContext) throws {
        for item in try modelContext.fetch(FetchDescriptor<ConversationItemModel>()) {
            modelContext.delete(item)
        }
        // Without its rows the cache promises nothing, so the next synchronization starts over.
        for state in try modelContext.fetch(FetchDescriptor<ConversationSyncStateModel>()) {
            modelContext.delete(state)
        }
        try modelContext.save()
        NotificationCenter.default.post(name: .communicatorConversationCacheCleared, object: nil)
    }
}

@ModelActor
actor SwiftDataConversationRepository: ConversationPersistence {
    func conversationWindow(
        serverURI: String,
        from start: Date?,
        newest limit: Int
    ) throws -> ConversationWindow {
        var descriptor = FetchDescriptor<ConversationItemModel>(
            predicate: Self.rows(serverURI: serverURI, from: start),
            sortBy: Self.newestFirst
        )
        if start == nil {
            descriptor.fetchLimit = limit
        }
        let rows = try modelContext.fetch(descriptor)
        let pending = try fetchPendingModels(serverURI: serverURI).map {
            try provisionalItem(for: $0)
        }
        let cachedRows = try modelContext.fetchCount(
            FetchDescriptor<ConversationItemModel>(
                predicate: #Predicate { $0.serverURI == serverURI }
            )
        )
        let state = try fetchSyncStateModel(serverURI: serverURI)
        return ConversationWindow(
            items: (try rows.map { try $0.item } + pending).sorted(by: Self.ordersBefore),
            start: rows.last?.createdAt,
            hasOlder: cachedRows > rows.count || state?.reachedBeginning == false
        )
    }

    func windowStart(
        serverURI: String,
        before date: Date,
        count: Int
    ) throws -> (start: Date?, found: Int) {
        var descriptor = FetchDescriptor<ConversationItemModel>(
            predicate: #Predicate { $0.serverURI == serverURI && $0.createdAt < date },
            sortBy: Self.newestFirst
        )
        descriptor.fetchLimit = count
        let rows = try modelContext.fetch(descriptor)
        return (rows.last?.createdAt, rows.count)
    }

    func syncState(serverURI: String) throws -> ConversationSyncState? {
        try fetchSyncStateModel(serverURI: serverURI)?.state
    }

    func pendingUtterances(serverURI: String) throws -> [PersonUtterance] {
        try fetchPendingModels(serverURI: serverURI).map { try $0.utterance }
    }

    func enqueue(
        _ utterance: PersonUtterance,
        inReplyTo itemID: ConversationItemID?,
        serverURI: String
    ) throws {
        modelContext.insert(
            try PendingUtteranceModel(
                utterance: utterance,
                inReplyToItemID: itemID,
                serverURI: serverURI
            )
        )
        try modelContext.save()
    }

    func accept(_ result: UtteranceIngressResult, serverURI: String) throws {
        try upsert([result.conversationItem], serverURI: serverURI)
        let storageID = PendingUtteranceModel.storageID(
            serverURI: serverURI,
            utteranceID: result.percept.utterance.utteranceID
        )
        var descriptor = FetchDescriptor<PendingUtteranceModel>(
            predicate: #Predicate { $0.id == storageID }
        )
        descriptor.fetchLimit = 1
        if let pending = try modelContext.fetch(descriptor).first {
            modelContext.delete(pending)
        }
        try modelContext.save()
    }

    func startHistory(
        with page: ConversationItemPage,
        serverURI: String
    ) throws -> ConversationSyncState {
        // A cache that predates this state, or history the World has replaced, can't promise it
        // has no gaps. Older rows come back by scrolling.
        let kept = page.items.map {
            ConversationItemModel.storageID(serverURI: serverURI, itemID: $0.itemID)
        }
        for row in try modelContext.fetch(
            FetchDescriptor<ConversationItemModel>(
                predicate: #Predicate { $0.serverURI == serverURI && !kept.contains($0.id) }
            )
        ) {
            modelContext.delete(row)
        }
        try upsert(page.items, serverURI: serverURI)
        let state = ConversationSyncState(
            newestItemID: page.items.last?.itemID,
            oldestItemID: page.items.first?.itemID,
            reachedBeginning: !page.hasMore
        )
        if let existing = try fetchSyncStateModel(serverURI: serverURI) {
            existing.state = state
        } else {
            modelContext.insert(ConversationSyncStateModel(serverURI: serverURI, state: state))
        }
        try modelContext.save()
        return state
    }

    func cacheNewer(_ items: [ConversationItem], serverURI: String) throws {
        // No state means the cache was cleared while this page was on its way.
        guard let model = try fetchSyncStateModel(serverURI: serverURI), !items.isEmpty else {
            return
        }
        try upsert(items, serverURI: serverURI)
        var state = model.state
        state.newestItemID = items.last?.itemID
        state.oldestItemID = state.oldestItemID ?? items.first?.itemID
        model.state = state
        try modelContext.save()
    }

    func cacheOlder(
        _ page: ConversationItemPage,
        before anchor: ConversationItemID?,
        serverURI: String
    ) throws {
        guard let model = try fetchSyncStateModel(serverURI: serverURI),
            model.state.oldestItemID == anchor
        else { return }
        try upsert(page.items, serverURI: serverURI)
        var state = model.state
        state.oldestItemID = page.items.first?.itemID ?? anchor
        state.reachedBeginning = !page.hasMore
        model.state = state
        try modelContext.save()
    }

    private static let newestFirst = [
        SortDescriptor(\ConversationItemModel.createdAt, order: .reverse),
        SortDescriptor(\ConversationItemModel.id, order: .reverse),
    ]

    private static func rows(
        serverURI: String,
        from start: Date?
    ) -> Predicate<ConversationItemModel> {
        guard let start else { return #Predicate { $0.serverURI == serverURI } }
        return #Predicate { $0.serverURI == serverURI && $0.createdAt >= start }
    }

    private func fetchSyncStateModel(serverURI: String) throws -> ConversationSyncStateModel? {
        var descriptor = FetchDescriptor<ConversationSyncStateModel>(
            predicate: #Predicate { $0.serverURI == serverURI }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchPendingModels(serverURI: String) throws -> [PendingUtteranceModel] {
        try modelContext.fetch(
            FetchDescriptor<PendingUtteranceModel>(
                predicate: #Predicate { $0.serverURI == serverURI },
                sortBy: [
                    SortDescriptor(\PendingUtteranceModel.occurredAt),
                    SortDescriptor(\PendingUtteranceModel.id),
                ]
            )
        )
    }

    /// One query for the whole page. Rows that haven't changed are left alone.
    private func upsert(_ items: [ConversationItem], serverURI: String) throws {
        let storageIDs = items.map {
            ConversationItemModel.storageID(serverURI: serverURI, itemID: $0.itemID)
        }
        let existing = Dictionary(
            try modelContext.fetch(
                FetchDescriptor<ConversationItemModel>(
                    predicate: #Predicate { storageIDs.contains($0.id) }
                )
            ).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (storageID, item) in zip(storageIDs, items) {
            if let row = existing[storageID] {
                try row.update(with: item)
            } else {
                modelContext.insert(try ConversationItemModel(item: item, serverURI: serverURI))
            }
        }
    }

    private func provisionalItem(for pending: PendingUtteranceModel) throws -> ConversationItem {
        let utterance = try pending.utterance
        return try ConversationItem(
            itemID: ConversationItemID(
                validating: "conversation-item:\(utterance.utteranceID.rawValue)"
            ),
            conversationID: utterance.conversationID,
            authorID: utterance.speakerID,
            authorKind: .person,
            text: utterance.text,
            createdAt: utterance.occurredAt,
            inReplyToItemID: try pending.inReplyToItemID.map(ConversationItemID.init(validating:)),
            utteranceID: utterance.utteranceID,
            trace: utterance.trace
        )
    }

    private static func ordersBefore(_ lhs: ConversationItem, _ rhs: ConversationItem) -> Bool {
        (lhs.createdAt, lhs.itemID.rawValue) < (rhs.createdAt, rhs.itemID.rawValue)
    }
}

private enum ConversationIdentity {
    static let conversationID = try! ConversationID(validating: "conversation:april-house")
    static let aprilID = try! EntityID(validating: "person:april")
    static let beakyID = try! EntityID(validating: "character:beaky")
    static let sourceID = try! SourceID(validating: "communicator:beaky-app")
}
