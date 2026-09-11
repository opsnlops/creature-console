import Foundation
import Testing
import WorldCore

@testable import Beaky_Communicator

@Suite("Beaky Communicator synchronization")
struct ConversationSynchronizationTests {
    @Test("A deterministic remote response becomes canonical conversation state")
    func synchronizesWithTestOnlyCharacterResponse() async throws {
        let persistence = TestConversationPersistence()
        let client = DeterministicConversationClient()
        let service = LiveCommunicatorConversationService(
            persistence: persistence,
            clientProvider: TestClientProvider(client: client)
        )

        try await service.submit(text: "Hello over the wire", inReplyTo: nil)
        let items = try await service.conversation()

        #expect(items.map(\.authorKind) == [.person, .character])
        #expect(items.map(\.text) == ["Hello over the wire", "Test-only response"])
        #expect(await client.submittedUtteranceIDs.count == 1)
        #expect(await persistence.pendingUtterances(serverURI: "test://world").isEmpty)
    }

    @Test("A new device backfills every page of canonical conversation history")
    func newDeviceBackfillsFullHistory() async throws {
        let remoteItems = try (0..<205).map(Self.makeHistoricalItem)
        let persistence = TestConversationPersistence()
        let client = PaginatedConversationClient(items: remoteItems)
        let service = LiveCommunicatorConversationService(
            persistence: persistence,
            clientProvider: PaginatedClientProvider(client: client)
        )

        let synchronized = try await service.conversation()

        #expect(synchronized == remoteItems)
        #expect(
            await client.requestedCursors == [
                nil,
                remoteItems[99].itemID,
                remoteItems[199].itemID,
            ]
        )
    }

    @Test("An unseen remote turn is not skipped when this device sends during catch-up")
    func sendingWhileBehindPreservesRemoteTurn() async throws {
        let initial = try Self.makeHistoricalItem(index: 0)
        let unseen = try Self.makeHistoricalItem(index: 1)
        let persistence = TestConversationPersistence()
        let client = PaginatedConversationClient(items: [initial])
        let service = LiveCommunicatorConversationService(
            persistence: persistence,
            clientProvider: PaginatedClientProvider(client: client)
        )
        _ = try await service.conversation()
        await client.append(unseen)

        try await service.submit(text: "Sent from this device", inReplyTo: nil)
        let synchronized = try await service.conversation()

        #expect(synchronized.map(\.text) == ["Message 0", "Message 1", "Sent from this device"])
        #expect(await client.requestedCursors.prefix(2) == [nil, initial.itemID])
    }

    @Test("Two connected devices converge on each other's new turns")
    func connectedDevicesConverge() async throws {
        let client = PaginatedConversationClient(items: [])
        let provider = PaginatedClientProvider(client: client)
        let phone = LiveCommunicatorConversationService(
            persistence: TestConversationPersistence(),
            clientProvider: provider
        )
        let mac = LiveCommunicatorConversationService(
            persistence: TestConversationPersistence(),
            clientProvider: provider
        )
        _ = try await phone.conversation()
        _ = try await mac.conversation()

        try await phone.submit(text: "Hello from iPhone", inReplyTo: nil)
        #expect(try await mac.conversation().map(\.text) == ["Hello from iPhone"])

        try await mac.submit(text: "Hello from Mac", inReplyTo: nil)
        #expect(
            try await phone.conversation().map(\.text) == [
                "Hello from iPhone", "Hello from Mac",
            ]
        )
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

    init(items: [ConversationItem]) {
        storedItems = items
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
    ) -> ConversationItemPage {
        requestedCursors.append(itemID)
        let start =
            itemID.flatMap { id in storedItems.firstIndex { $0.itemID == id } }
            .map { $0 + 1 } ?? 0
        let remaining = storedItems.dropFirst(start)
        let pageItems = Array(remaining.prefix(limit))
        return ConversationItemPage(
            items: pageItems,
            nextItemID: pageItems.last?.itemID,
            hasMore: remaining.count > limit
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
}

private actor TestConversationPersistence: ConversationPersistence {
    private var items: [String: [ConversationItem]] = [:]
    private var pending: [String: [UtteranceID: PersonUtterance]] = [:]

    func conversation(serverURI: String) -> [ConversationItem] {
        items[serverURI, default: []].sorted {
            ($0.createdAt, $0.itemID.rawValue) < ($1.createdAt, $1.itemID.rawValue)
        }
    }

    func pendingUtterances(serverURI: String) -> [PersonUtterance] {
        pending[serverURI, default: [:]].values.sorted { $0.occurredAt < $1.occurredAt }
    }

    func latestCachedItemID(serverURI: String) -> ConversationItemID? {
        conversation(serverURI: serverURI).last?.itemID
    }

    func enqueue(
        _ utterance: PersonUtterance,
        inReplyTo itemID: ConversationItemID?,
        serverURI: String
    ) {
        pending[serverURI, default: [:]][utterance.utteranceID] = utterance
    }

    func accept(_ result: UtteranceIngressResult, serverURI: String) {
        upsert(result.conversationItem, serverURI: serverURI)
        pending[serverURI, default: [:]][result.percept.utterance.utteranceID] = nil
    }

    func cache(_ items: [ConversationItem], serverURI: String) {
        for item in items { upsert(item, serverURI: serverURI) }
    }

    private func upsert(_ item: ConversationItem, serverURI: String) {
        items[serverURI, default: []].removeAll { $0.itemID == item.itemID }
        items[serverURI, default: []].append(item)
    }
}
