import CreatureAppSupport
import Foundation
import Testing
import WorldCore

@testable import Flock_Communicator

@MainActor
@Suite("Flock Communicator conversation store")
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

    @Test("The cache shows before the network answers")
    func showsCacheFirst() async throws {
        let cached = try makeCharacterItem(text: "From the cache")
        let service = HeldConversationService(cached: [cached])
        let store = ConversationStore(service: service)

        let loading = Task { await store.load() }
        await service.waitForNetworkRead()

        #expect(store.items == [cached])
        #expect(!store.isLoading)
        await service.release()
        await loading.value
    }

    @Test("The spinner is for an empty cache")
    func spinsOnlyWhenEmpty() async throws {
        let service = HeldConversationService(cached: [])
        let store = ConversationStore(service: service)

        let loading = Task { await store.load() }
        await service.waitForNetworkRead()

        #expect(store.isLoading)
        await service.release()
        await loading.value
        #expect(!store.isLoading)
    }

    @Test("Loading older history replaces the window and tracks what remains")
    func loadsOlder() async throws {
        let older = try makeCharacterItem(
            text: "Older",
            suffix: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            createdAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
        let newer = try makeCharacterItem(text: "Newer")
        let service = TestConversationService(items: [newer], hasOlder: true)
        let store = ConversationStore(service: service)
        await store.load()
        #expect(store.hasOlderHistory)

        await service.setOlder(ConversationWindow(items: [older, newer], hasOlder: false))
        await store.loadOlder()

        #expect(store.items == [older, newer])
        #expect(!store.hasOlderHistory)
    }

    @Test("Older history that can't load offers a retry rather than an alert")
    func olderFailureOffersRetry() async throws {
        let item = try makeCharacterItem(text: "Hello")
        let service = TestConversationService(items: [item], hasOlder: true)
        let store = ConversationStore(service: service)
        await store.load()

        await service.setOlderFailure(URLError(.notConnectedToInternet))
        await store.loadOlder()

        #expect(store.olderHistoryFailed)
        #expect(store.errorAlert == nil)
        #expect(store.items == [item])

        await service.setOlderFailure(nil)
        await service.setOlder(ConversationWindow(items: [item], hasOlder: false))
        await store.loadOlder()
        #expect(!store.olderHistoryFailed)
    }

    @Test("A refresh that began before a scroll back cannot undo it")
    func staleWindowIsIgnored() async throws {
        let older = try makeCharacterItem(
            text: "Older",
            suffix: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            createdAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
        let newer = try makeCharacterItem(text: "Newer")
        let service = TestConversationService(items: [newer], hasOlder: true)
        let store = ConversationStore(service: service)
        await store.load()

        await service.setOlder(ConversationWindow(items: [older, newer], revision: 5))
        await store.loadOlder()
        await service.setRevision(4)
        await store.refresh()

        #expect(store.items == [older, newer])
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

    func conversation() -> ConversationWindow { ConversationWindow() }

    func cachedConversation() -> ConversationWindow { ConversationWindow() }

    func olderConversation() -> ConversationWindow { ConversationWindow() }

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

/// Holds the network read open, so a test can look at what shows while it waits.
private actor HeldConversationService: CommunicatorConversationService {
    private let cached: [ConversationItem]
    private let reads: AsyncStream<Void>
    private let readContinuation: AsyncStream<Void>.Continuation
    private let releases: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init(cached: [ConversationItem]) {
        self.cached = cached
        (reads, readContinuation) = AsyncStream.makeStream()
        (releases, releaseContinuation) = AsyncStream.makeStream()
    }

    func conversation() async -> ConversationWindow {
        readContinuation.yield()
        for await _ in releases { break }
        return ConversationWindow(items: cached)
    }

    func cachedConversation() -> ConversationWindow { ConversationWindow(items: cached) }

    func olderConversation() -> ConversationWindow { ConversationWindow(items: cached) }

    func submit(text: String, inReplyTo item: ConversationItem?) {}

    func waitForNetworkRead() async {
        for await _ in reads { break }
    }

    func release() {
        releaseContinuation.yield()
    }
}

private actor TestConversationService: CommunicatorConversationService {
    struct Submission: Sendable {
        let text: String
        let replyItemID: ConversationItemID?
    }

    private var items: [ConversationItem]
    private var hasOlder: Bool
    private var revision = 0
    private var older = ConversationWindow()
    private var olderFailure: (any Error)?
    private(set) var submission: Submission?

    init(items: [ConversationItem], hasOlder: Bool = false) {
        self.items = items
        self.hasOlder = hasOlder
    }

    func conversation() -> ConversationWindow {
        ConversationWindow(items: items, hasOlder: hasOlder, revision: revision)
    }

    func cachedConversation() -> ConversationWindow { conversation() }

    func olderConversation() throws -> ConversationWindow {
        if let olderFailure { throw olderFailure }
        return older
    }

    func submit(text: String, inReplyTo item: ConversationItem?) {
        submission = Submission(text: text, replyItemID: item?.itemID)
    }

    func replaceItems(with items: [ConversationItem]) {
        self.items = items
    }

    func setOlder(_ window: ConversationWindow) {
        older = window
    }

    func setOlderFailure(_ error: (any Error)?) {
        olderFailure = error
    }

    func setRevision(_ revision: Int) {
        self.revision = revision
    }
}
