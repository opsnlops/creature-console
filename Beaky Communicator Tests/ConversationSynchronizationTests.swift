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
        #expect(try await persistence.pendingUtterances().isEmpty)
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
    private var items: [ConversationItem] = []
    private var pending: [UtteranceID: PersonUtterance] = [:]

    func conversation() -> [ConversationItem] {
        items.sorted { ($0.createdAt, $0.itemID.rawValue) < ($1.createdAt, $1.itemID.rawValue) }
    }

    func pendingUtterances() -> [PersonUtterance] {
        pending.values.sorted { $0.occurredAt < $1.occurredAt }
    }

    func enqueue(_ utterance: PersonUtterance, inReplyTo itemID: ConversationItemID?) {
        pending[utterance.utteranceID] = utterance
    }

    func accept(_ result: UtteranceIngressResult) {
        upsert(result.conversationItem)
        pending[result.percept.utterance.utteranceID] = nil
    }

    func cache(_ items: [ConversationItem]) {
        for item in items { upsert(item) }
    }

    private func upsert(_ item: ConversationItem) {
        items.removeAll { $0.itemID == item.itemID }
        items.append(item)
    }
}
