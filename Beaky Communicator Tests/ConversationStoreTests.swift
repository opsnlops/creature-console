import Foundation
import Testing
import WorldCore

@testable import Beaky_Communicator

@MainActor
@Suite("Beaky Communicator conversation store")
struct ConversationStoreTests {
    @Test("Loading exposes the service's ordered WorldCore conversation")
    func loadsConversation() async throws {
        let item = try makeCharacterItem(text: "Hello, April")
        let service = TestConversationService(items: [item])
        let store = ConversationStore(service: service)

        await store.load()

        #expect(store.items == [item])
        #expect(store.errorAlert == nil)
    }

    @Test("Sending trims the draft and preserves reply identity")
    func sendsReply() async throws {
        let item = try makeCharacterItem(text: "What do you think?")
        let service = TestConversationService(items: [item])
        let store = ConversationStore(service: service)
        await store.load()
        store.draft = "  I love it.  "
        store.replyingTo = item

        await store.send()

        let submission = await service.submission
        #expect(submission?.text == "I love it.")
        #expect(submission?.replyItemID == item.itemID)
        #expect(store.draft.isEmpty)
        #expect(store.replyingTo == nil)
    }

    private func makeCharacterItem(text: String) throws -> ConversationItem {
        let responseUUID = try #require(
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        )
        return try ConversationItem(
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            authorID: EntityID(validating: "character:beaky"),
            authorKind: .character,
            text: text,
            createdAt: Date(timeIntervalSince1970: 1_789_000_000),
            responseID: .generated(using: responseUUID)
        )
    }
}

private actor TestConversationService: CommunicatorConversationService {
    struct Submission: Sendable {
        let text: String
        let replyItemID: ConversationItemID?
    }

    private var items: [ConversationItem]
    private(set) var submission: Submission?

    init(items: [ConversationItem]) {
        self.items = items
    }

    func conversation() -> [ConversationItem] {
        items
    }

    func submit(text: String, inReplyTo item: ConversationItem?) {
        submission = Submission(text: text, replyItemID: item?.itemID)
    }
}
