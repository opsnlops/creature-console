import CreatureAppSupport
import Foundation
import SwiftData
import Testing
import WorldCore

@testable import Flock_Communicator

@Suite("Flock Communicator synchronization")
struct ConversationSynchronizationTests {
    private static let serverURI = "test://world"

    @Test("A deterministic remote response becomes canonical conversation state")
    func synchronizesWithTestOnlyCharacterResponse() async throws {
        let persistence = try Self.makeRepository()
        let client = DeterministicConversationClient()
        let service = LiveCommunicatorConversationService(
            persistence: persistence,
            clientProvider: TestClientProvider(client: client)
        )

        try await service.submit(text: "Hello over the wire", inReplyTo: nil)
        let items = try await service.conversation().items

        #expect(items.map(\.authorKind) == [.person, .character])
        #expect(items.map(\.text) == ["Hello over the wire", "Test-only response"])
        #expect(await client.submittedUtteranceIDs.count == 1)
        #expect(try await persistence.pendingUtterances(serverURI: Self.serverURI).isEmpty)
    }

    @Test("A new device fetches the newest page and none of the past")
    func newDeviceFetchesOnePage() async throws {
        let remoteItems = try Self.makeHistory(count: 1_000)
        let client = PaginatedConversationClient(items: remoteItems)
        let service = try Self.makeService(client: client)

        let window = try await service.conversation()

        #expect(window.items == Array(remoteItems.suffix(ConversationPaging.pageSize)))
        #expect(window.hasOlder)
        #expect(await client.backwardCursors == [nil])
        #expect(await client.requestedCursors == [remoteItems.last?.itemID])
    }

    @Test("Scrolling up reaches the very first message, a page at a time")
    func scrollingReachesTheBeginning() async throws {
        let remoteItems = try Self.makeHistory(count: 450)
        let client = PaginatedConversationClient(items: remoteItems)
        let service = try Self.makeService(client: client)
        var window = try await service.conversation()
        var pages = 0

        while window.hasOlder {
            window = try await service.olderConversation()
            pages += 1
            #expect(pages < 10)
        }

        #expect(window.items == remoteItems)
        #expect(pages == 2)
        #expect(
            await client.backwardCursors == [
                nil, remoteItems[250].itemID, remoteItems[50].itemID,
            ]
        )
    }

    @Test("Relaunching fetches only what arrived since")
    func relaunchResumes() async throws {
        let remoteItems = try Self.makeHistory(count: 300)
        let client = PaginatedConversationClient(items: remoteItems)
        let persistence = try Self.makeRepository()
        _ = try await Self.makeService(client: client, persistence: persistence).conversation()
        let unseen = try Self.makeHistoricalItem(index: 300)
        await client.append(unseen)
        await client.forgetRequests()

        let relaunched = try await Self.makeService(client: client, persistence: persistence)
            .conversation()

        #expect(relaunched.items.last == unseen)
        #expect(await client.backwardCursors.isEmpty)
        #expect(await client.requestedCursors == [remoteItems.last?.itemID])
    }

    @Test("The window shows cached rows without the network, and reads only a page of them")
    func cachedConversationNeedsNoNetwork() async throws {
        let remoteItems = try Self.makeHistory(count: 300)
        let client = PaginatedConversationClient(items: remoteItems)
        let persistence = try Self.makeRepository()
        let service = try Self.makeService(client: client, persistence: persistence)
        _ = try await service.conversation()
        _ = try await service.olderConversation()
        await client.forgetRequests()

        let relaunched = try Self.makeService(client: client, persistence: persistence)
        let window = try await relaunched.cachedConversation()

        #expect(window.items == Array(remoteItems.suffix(ConversationPaging.pageSize)))
        #expect(window.hasOlder)
        #expect(await client.requestedCursors.isEmpty)
        #expect(await client.backwardCursors.isEmpty)
    }

    @Test("A turn sent past a gap does not hide the gap, even across a relaunch")
    func sentTurnNeverBecomesTheCursor() async throws {
        let initial = try Self.makeHistoricalItem(index: 0)
        let unseen = try Self.makeHistoricalItem(index: 1)
        let client = PaginatedConversationClient(items: [initial])
        let persistence = try Self.makeRepository()
        let service = try Self.makeService(client: client, persistence: persistence)
        _ = try await service.conversation()
        await client.append(unseen)

        // The turn is accepted, then the connection drops before the history can follow.
        await client.failNextReads(with: URLError(.notConnectedToInternet))
        try await service.submit(text: "Sent from this device", inReplyTo: nil)

        let relaunched = try await Self.makeService(client: client, persistence: persistence)
            .conversation()

        #expect(
            relaunched.items.map(\.text) == ["Message 0", "Message 1", "Sent from this device"])
    }

    @Test("An unseen remote turn is not skipped when this device sends during catch-up")
    func sendingWhileBehindPreservesRemoteTurn() async throws {
        let initial = try Self.makeHistoricalItem(index: 0)
        let unseen = try Self.makeHistoricalItem(index: 1)
        let client = PaginatedConversationClient(items: [initial])
        let service = try Self.makeService(client: client)
        _ = try await service.conversation()
        await client.append(unseen)

        try await service.submit(text: "Sent from this device", inReplyTo: nil)
        let synchronized = try await service.conversation()

        #expect(
            synchronized.items.map(\.text) == ["Message 0", "Message 1", "Sent from this device"]
        )
        #expect(await client.requestedCursors.prefix(2) == [initial.itemID, initial.itemID])
    }

    @Test("An interrupted catch-up resumes where it stopped")
    func interruptedCatchUpResumes() async throws {
        let first = try Self.makeHistory(count: 10)
        let client = PaginatedConversationClient(items: first)
        let persistence = try Self.makeRepository()
        let service = try Self.makeService(client: client, persistence: persistence)
        _ = try await service.conversation()
        let away = try (10..<510).map(Self.makeHistoricalItem)
        for item in away { await client.append(item) }
        await client.forgetRequests()

        await client.failReads(after: 1, with: URLError(.networkConnectionLost))
        _ = try await service.conversation()
        await client.forgetRequests()
        let resumed = try await service.conversation()

        #expect(await client.requestedCursors.first == away[199].itemID)
        #expect(resumed.items.last == away.last)
    }

    @Test("A cursor the World rejects starts over; a dropped connection does not")
    func onlyARejectedCursorStartsOver() async throws {
        let remoteItems = try Self.makeHistory(count: 5)
        let client = PaginatedConversationClient(items: remoteItems)
        let service = try Self.makeService(client: client)
        _ = try await service.conversation()
        await client.forgetRequests()

        await client.failNextReads(with: URLError(.timedOut))
        let offline = try await service.conversation()
        #expect(offline.items == remoteItems)
        #expect(await client.backwardCursors.isEmpty)

        let replaced = try (100..<103).map(Self.makeHistoricalItem)
        await client.replaceHistory(with: replaced)
        let recovered = try await service.conversation()

        #expect(recovered.items == replaced)
        #expect(await client.backwardCursors == [nil])
    }

    @Test("A cache from before paged history gives way at the first good sync")
    func unprovenCacheStartsOver() async throws {
        let oldRows = try Self.makeHistory(count: 3)
        let remoteItems = try (100..<105).map(Self.makeHistoricalItem)
        let client = PaginatedConversationClient(items: remoteItems)
        let container = try Self.makeContainer()
        let persistence = SwiftDataConversationRepository(modelContainer: container)
        try await Self.seedLegacyRows(oldRows, in: container)
        let service = try Self.makeService(client: client, persistence: persistence)

        // Offline, the old rows are all there is, so they show.
        await client.failNextReads(with: URLError(.notConnectedToInternet))
        #expect(try await service.conversation().items == oldRows)

        #expect(try await service.conversation().items == remoteItems)
    }

    @Test("Clearing the cache starts over and keeps the outbox")
    func clearingStartsOver() async throws {
        let remoteItems = try Self.makeHistory(count: 300)
        let client = PaginatedConversationClient(items: remoteItems)
        let container = try Self.makeContainer()
        let persistence = SwiftDataConversationRepository(modelContainer: container)
        let service = try Self.makeService(client: client, persistence: persistence)
        _ = try await service.conversation()
        _ = try await service.olderConversation()
        await client.forgetRequests()

        try await MainActor.run {
            try ConversationCacheMaintenance.clear(using: container.mainContext)
        }
        let window = try await service.conversation()

        #expect(window.items == Array(remoteItems.suffix(ConversationPaging.pageSize)))
        #expect(await client.backwardCursors == [nil])
    }

    @Test("A new turn keeps what you scrolled back to on screen")
    func refreshKeepsTheExpandedWindow() async throws {
        let remoteItems = try Self.makeHistory(count: 300)
        let client = PaginatedConversationClient(items: remoteItems)
        let service = try Self.makeService(client: client)
        _ = try await service.conversation()
        let scrolled = try await service.olderConversation()
        #expect(scrolled.items == remoteItems)

        let newest = try Self.makeHistoricalItem(index: 300)
        await client.append(newest)
        let refreshed = try await service.conversation()

        #expect(refreshed.items == remoteItems + [newest])
    }

    @Test("Without scrolling, the window stays a page as turns arrive")
    func windowSlides() async throws {
        let remoteItems = try Self.makeHistory(count: 300)
        let client = PaginatedConversationClient(items: remoteItems)
        let service = try Self.makeService(client: client)
        _ = try await service.conversation()

        await client.append(try Self.makeHistoricalItem(index: 300))
        let window = try await service.conversation()

        #expect(window.items.count == ConversationPaging.pageSize)
        #expect(window.items.last?.text == "Message 300")
    }

    @Test("Scrolling up offline shows the rows still cached, then says it can't go on")
    func scrollingOffline() async throws {
        let remoteItems = try Self.makeHistory(count: 250)
        let client = PaginatedConversationClient(items: remoteItems)
        let persistence = try Self.makeRepository()
        let service = try Self.makeService(client: client, persistence: persistence)
        _ = try await service.conversation()
        _ = try await service.olderConversation()

        let relaunched = try Self.makeService(client: client, persistence: persistence)
        await client.failNextReads(with: URLError(.notConnectedToInternet), count: 2)
        let cached = try await relaunched.olderConversation()
        #expect(cached.items == remoteItems)

        let partial = try Self.makeHistory(count: 450)
        let shortClient = PaginatedConversationClient(items: partial)
        let shortService = try Self.makeService(client: shortClient)
        _ = try await shortService.conversation()
        await shortClient.failNextReads(with: URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) {
            try await shortService.olderConversation()
        }
        #expect(try await shortService.olderConversation().items.count == 400)
    }

    @Test("Rows sharing the window's edge all come along")
    func tiesAtTheWindowEdge() async throws {
        // Every row above the window shares the date of the window's oldest row, so nothing is
        // strictly older than it.
        let date = Date(timeIntervalSince1970: 3)
        var remoteItems = try Self.makeHistory(count: 203)
        for index in 0...3 { remoteItems[index].createdAt = date }
        let client = PaginatedConversationClient(items: remoteItems)
        let persistence = try Self.makeRepository()
        _ = try await persistence.startHistory(
            with: ConversationItemPage(
                items: remoteItems,
                nextItemID: remoteItems.first?.itemID,
                hasMore: false
            ),
            serverURI: Self.serverURI
        )
        let service = try Self.makeService(client: client, persistence: persistence)

        var window = try await service.cachedConversation()
        #expect(window.items.count == ConversationPaging.pageSize)
        for _ in 0..<3 where window.hasOlder {
            window = try await service.olderConversation()
        }

        #expect(window.items.count == remoteItems.count)
        #expect(!window.hasOlder)
    }

    @Test("A page the cache has moved past is dropped")
    func stalePageIsDropped() async throws {
        let remoteItems = try Self.makeHistory(count: 10)
        let persistence = try Self.makeRepository()
        let state = try await persistence.startHistory(
            with: ConversationItemPage(
                items: Array(remoteItems.suffix(5)),
                nextItemID: remoteItems[5].itemID,
                hasMore: true
            ),
            serverURI: Self.serverURI
        )

        try await persistence.cacheOlder(
            ConversationItemPage(items: [remoteItems[0]], nextItemID: nil, hasMore: false),
            before: remoteItems[1].itemID,
            serverURI: Self.serverURI
        )

        #expect(try await persistence.syncState(serverURI: Self.serverURI) == state)
    }

    @Test("Two connected devices converge on each other's new turns")
    func connectedDevicesConverge() async throws {
        let client = PaginatedConversationClient(items: [])
        let phone = try Self.makeService(client: client)
        let mac = try Self.makeService(client: client)
        _ = try await phone.conversation()
        _ = try await mac.conversation()

        try await phone.submit(text: "Hello from iPhone", inReplyTo: nil)
        #expect(try await mac.conversation().items.map(\.text) == ["Hello from iPhone"])

        try await mac.submit(text: "Hello from Mac", inReplyTo: nil)
        #expect(
            try await phone.conversation().items.map(\.text) == [
                "Hello from iPhone", "Hello from Mac",
            ]
        )
    }

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ConversationItemModel.self, PendingUtteranceModel.self,
            ConversationSyncStateModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static func makeRepository() throws -> SwiftDataConversationRepository {
        SwiftDataConversationRepository(modelContainer: try makeContainer())
    }

    private static func makeService(
        client: PaginatedConversationClient,
        persistence: SwiftDataConversationRepository? = nil
    ) throws -> LiveCommunicatorConversationService {
        LiveCommunicatorConversationService(
            persistence: try persistence ?? makeRepository(),
            clientProvider: PaginatedClientProvider(client: client)
        )
    }

    /// Rows as an older build left them: cached, with no state to vouch for them.
    @MainActor
    private static func seedLegacyRows(
        _ items: [ConversationItem],
        in container: ModelContainer
    ) throws {
        for item in items {
            container.mainContext.insert(
                try ConversationItemModel(item: item, serverURI: serverURI)
            )
        }
        try container.mainContext.save()
    }

    private static func makeHistory(count: Int) throws -> [ConversationItem] {
        try (0..<count).map(makeHistoricalItem)
    }

    private static func makeHistoricalItem(index: Int) throws -> ConversationItem {
        try ConversationItem(
            itemID: ConversationItemID(
                validating: "conversation-item:history-\(String(format: "%03d", index))"
            ),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            authorID: EntityID(validating: "person:april"),
            authorKind: .person,
            text: "Message \(index)",
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            utteranceID: UtteranceID(
                validating: "utterance:history-\(String(format: "%03d", index))"
            )
        )
    }
}

private struct PaginatedClientProvider: CommunicatorWorldClientProviding {
    let remote: PaginatedConversationClient

    init(client: PaginatedConversationClient) {
        remote = client
    }

    func client() -> any CommunicatorWorldClient { remote }
}

private actor PaginatedConversationClient: CommunicatorWorldClient {
    private var storedItems: [ConversationItem]
    private(set) var requestedCursors: [ConversationItemID?] = []
    private(set) var backwardCursors: [ConversationItemID?] = []
    private var readsBeforeFailure: Int?
    private var failuresLeft = 0
    private var failure: (any Error)?

    init(items: [ConversationItem]) {
        storedItems = items
    }

    func forgetRequests() {
        requestedCursors = []
        backwardCursors = []
    }

    func failNextReads(with error: any Error, count: Int = 1) {
        failReads(after: 0, with: error, count: count)
    }

    func failReads(after reads: Int, with error: any Error, count: Int = 1) {
        readsBeforeFailure = reads
        failuresLeft = count
        failure = error
    }

    func replaceHistory(with items: [ConversationItem]) {
        storedItems = items
    }

    private func readOrFail() throws {
        guard let reads = readsBeforeFailure, failuresLeft > 0, let failure else { return }
        guard reads == 0 else {
            readsBeforeFailure = reads - 1
            return
        }
        failuresLeft -= 1
        throw failure
    }

    func submit(_ utterance: PersonUtterance) throws -> UtteranceIngressResult {
        let item = try ConversationItem(
            itemID: ConversationItemID(
                validating: "conversation-item:\(utterance.utteranceID.rawValue)"
            ),
            conversationID: utterance.conversationID,
            authorID: utterance.speakerID,
            authorKind: .person,
            text: utterance.text,
            createdAt: utterance.occurredAt,
            utteranceID: utterance.utteranceID
        )
        storedItems.append(item)
        return UtteranceIngressResult(
            disposition: .accepted,
            percept: try PersonUtterancePercept(
                characterID: utterance.addresseeIDs[0],
                utterance: utterance,
                priorConversationItems: Array(storedItems.dropLast())
            ),
            conversationItem: item
        )
    }

    func append(_ item: ConversationItem) {
        storedItems.append(item)
    }

    func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) throws -> ConversationItemPage {
        try readOrFail()
        requestedCursors.append(itemID)
        var start = 0
        if let itemID {
            guard let anchor = storedItems.firstIndex(where: { $0.itemID == itemID }) else {
                throw WorldConversationClientError.requestFailed(statusCode: 400)
            }
            start = anchor + 1
        }
        let remaining = storedItems.dropFirst(start)
        let pageItems = Array(remaining.prefix(limit))
        return ConversationItemPage(
            items: pageItems,
            nextItemID: pageItems.last?.itemID,
            hasMore: remaining.count > limit
        )
    }

    func history(
        in conversationID: ConversationID,
        before itemID: ConversationItemID?,
        limit: Int
    ) throws -> ConversationItemPage {
        try readOrFail()
        backwardCursors.append(itemID)
        var end = storedItems.count
        if let itemID {
            guard let anchor = storedItems.firstIndex(where: { $0.itemID == itemID }) else {
                throw WorldConversationClientError.requestFailed(statusCode: 400)
            }
            end = anchor
        }
        let older = storedItems.prefix(end)
        let pageItems = Array(older.suffix(limit))
        return ConversationItemPage(
            items: pageItems,
            nextItemID: pageItems.first?.itemID,
            hasMore: older.count > limit
        )
    }
}

private struct TestClientProvider: CommunicatorWorldClientProviding {
    let remote: DeterministicConversationClient

    init(client: DeterministicConversationClient) {
        remote = client
    }

    func client() -> any CommunicatorWorldClient { remote }
}

private actor DeterministicConversationClient: CommunicatorWorldClient {
    private var personItem: ConversationItem?
    private var characterItem: ConversationItem?
    private(set) var submittedUtteranceIDs: [UtteranceID] = []

    func submit(_ utterance: PersonUtterance) throws -> UtteranceIngressResult {
        submittedUtteranceIDs.append(utterance.utteranceID)
        let personItem = try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:test-person"),
            conversationID: utterance.conversationID,
            authorID: utterance.speakerID,
            authorKind: .person,
            text: utterance.text,
            createdAt: utterance.occurredAt,
            utteranceID: utterance.utteranceID
        )
        let characterItem = try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:test-character"),
            conversationID: utterance.conversationID,
            authorID: utterance.addresseeIDs[0],
            authorKind: .character,
            text: "Test-only response",
            createdAt: utterance.occurredAt.addingTimeInterval(1),
            inReplyToItemID: personItem.itemID,
            responseID: ResponseID(validating: "response:test-character")
        )
        self.personItem = personItem
        self.characterItem = characterItem
        return UtteranceIngressResult(
            disposition: .accepted,
            percept: try PersonUtterancePercept(
                characterID: utterance.addresseeIDs[0],
                utterance: utterance,
                priorConversationItems: []
            ),
            conversationItem: personItem
        )
    }

    func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) -> ConversationItemPage {
        let allItems = [personItem, characterItem].compactMap { $0 }
        let start =
            itemID.flatMap { id in allItems.firstIndex { $0.itemID == id } }
            .map { $0 + 1 } ?? 0
        let remaining = Array(allItems.dropFirst(start))
        let pageItems = Array(remaining.prefix(limit))
        return ConversationItemPage(
            items: pageItems,
            nextItemID: pageItems.last?.itemID,
            hasMore: remaining.count > limit
        )
    }

    func history(
        in conversationID: ConversationID,
        before itemID: ConversationItemID?,
        limit: Int
    ) -> ConversationItemPage {
        let allItems = [personItem, characterItem].compactMap { $0 }
        return ConversationItemPage(
            items: allItems,
            nextItemID: allItems.first?.itemID,
            hasMore: false
        )
    }
}
