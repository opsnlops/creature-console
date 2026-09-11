import CreatureAppSupport
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

    @Test("Refreshing catches up with conversation changes from another device")
    func refreshesConversation() async throws {
        let first = try makeCharacterItem(text: "Hello, April")
        let second = try makeCharacterItem(
            text: "I saw your message from the iPhone",
            suffix: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            createdAt: Date(timeIntervalSince1970: 1_789_000_001)
        )
        let service = TestConversationService(items: [first])
        let store = ConversationStore(service: service)
        await store.load()

        await service.replaceItems(with: [first, second])
        await store.refresh()

        #expect(store.items == [first, second])
    }

    @Test("Live updates expose connected and reconnecting states")
    func reportsConnectionState() async {
        let service = StreamingConversationService()
        let store = ConversationStore(service: service)
        let observation = Task { await store.observeUpdates() }

        await service.signalConnection()
        await waitUntil { store.connectionState == .connected }
        #expect(store.connectionState == .connected)

        await service.disconnect()
        await waitUntil { store.connectionState == .reconnecting }
        #expect(store.connectionState == .reconnecting)

        observation.cancel()
        await observation.value
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    private func makeCharacterItem(
        text: String,
        suffix: String = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        createdAt: Date = Date(timeIntervalSince1970: 1_789_000_000)
    ) throws -> ConversationItem {
        let responseUUID = try #require(
            UUID(uuidString: suffix)
        )
        return try ConversationItem(
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            authorID: EntityID(validating: "character:beaky"),
            authorKind: .character,
            text: text,
            createdAt: createdAt,
            responseID: .generated(using: responseUUID)
        )
    }
}

private actor StreamingConversationService: CommunicatorConversationService {
    private let stream: WorldConversationUpdateStream
    private let continuation: WorldConversationUpdateStream.Continuation

    init() {
        (stream, continuation) = WorldConversationUpdateStream.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func conversation() -> [ConversationItem] { [] }

    func submit(text: String, inReplyTo item: ConversationItem?) {}

    func updates() -> WorldConversationUpdateStream { stream }

    func signalConnection() {
        continuation.yield(())
    }

    func disconnect() {
        continuation.finish(throwing: StreamingTestError.disconnected)
    }
}

private enum StreamingTestError: Error {
    case disconnected
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

    func replaceItems(with items: [ConversationItem]) {
        self.items = items
    }
}
