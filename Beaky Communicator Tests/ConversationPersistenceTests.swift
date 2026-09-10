import Foundation
import SwiftData
import Testing
import WorldCore

@testable import Beaky_Communicator

@MainActor
@Suite("Beaky Communicator conversation persistence", .serialized)
struct ConversationPersistenceTests {
    @Test("Proxy routing does not create a different World cache partition")
    func proxyRoutingPreservesLogicalServerURI() throws {
        let suiteName = "CommunicatorConnectionProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("SERVER.PROD.CHIRPCHIRP.DEV", forKey: "worldServerAddress")
        defaults.set(443, forKey: "worldServerPort")
        defaults.set(true, forKey: "worldServerUseTLS")
        defaults.set("proxy.prod.chirpchirp.dev", forKey: "worldServerProxyHost")
        let provider = CommunicatorConnectionProvider(defaults: defaults, keyStore: nil)

        defaults.set(false, forKey: "worldServerUseProxy")
        let directURI = provider.serverURI()
        defaults.set(true, forKey: "worldServerUseProxy")
        let proxiedURI = provider.serverURI()

        #expect(directURI == "https://server.prod.chirpchirp.dev:443/world/v1")
        #expect(proxiedURI == directURI)
    }

    @Test("SwiftData model preserves the complete WorldCore conversation item")
    func modelRoundTrip() throws {
        let item = try Self.makeItem()

        let model = try ConversationItemModel(item: item, serverURI: "https://world.example/v1")

        #expect(try model.item == item)
    }

    @Test("SwiftData model reads conversation rows written before RFC 3339 wire storage")
    func readsLegacyDateEncoding() throws {
        let item = try Self.makeItem()
        let model = try ConversationItemModel(item: item, serverURI: "https://world.example/v1")
        model.payload = try JSONEncoder().encode(item)

        #expect(try model.item == item)
    }

    private static func makeItem() throws -> ConversationItem {
        try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:persistence-test"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            authorID: EntityID(validating: "character:beaky"),
            authorKind: .character,
            text: "I will remember this.",
            createdAt: Date(timeIntervalSince1970: 1_789_010_000),
            responseID: ResponseID(validating: "response:persistence-test")
        )
    }

    @Test("Offline outbox survives reopening the on-disk SwiftData store")
    func outboxSurvivesApplicationRestart() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory.appending(
            path: "beaky-communicator-persistence-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let storeURL = storeDirectory.appending(path: "conversation.store")
        try await writeConversation(to: storeURL)

        let reopenedContainer = try ModelContainer(
            for: ConversationItemModel.self, PendingUtteranceModel.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let reopenedRepository = SwiftDataConversationRepository(modelContainer: reopenedContainer)
        let serverURI = "https://world.example/v1"
        let restoredItems = try await reopenedRepository.conversation(serverURI: serverURI)
        #expect(restoredItems.map(\.text) == ["Yes, please remember."])
        #expect(restoredItems.only?.authorKind == .person)
        #expect(try await reopenedRepository.latestCachedItemID(serverURI: serverURI) == nil)
    }

    @Test("Conversation cache and outbox are partitioned by World server URI")
    func partitionsApplicationDataByServerURI() async throws {
        let container = try ModelContainer(
            for: ConversationItemModel.self, PendingUtteranceModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = SwiftDataConversationRepository(modelContainer: container)
        let developmentURI = "http://10.69.66.1:8000/world/v1"
        let productionURI = "https://server.prod.chirpchirp.dev:443/world/v1"
        var developmentItem = try Self.makeItem()
        developmentItem.text = "Development history"
        var productionItem = developmentItem
        productionItem.text = "Production history"

        try await repository.cache([developmentItem], serverURI: developmentURI)
        try await repository.cache([productionItem], serverURI: productionURI)

        #expect(
            try await repository.conversation(serverURI: developmentURI).map(\.text)
                == ["Development history"]
        )
        #expect(
            try await repository.conversation(serverURI: productionURI).map(\.text)
                == ["Production history"]
        )
        #expect(
            try await repository.latestCachedItemID(serverURI: developmentURI)
                == developmentItem.itemID
        )

        let pending = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Only send me to development",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_010_200),
            confidence: 1
        )
        try await repository.enqueue(pending, inReplyTo: nil, serverURI: developmentURI)

        #expect(try await repository.pendingUtterances(serverURI: productionURI).isEmpty)
        #expect(
            try await repository.pendingUtterances(serverURI: developmentURI).map(\.text)
                == ["Only send me to development"]
        )

        try ConversationCacheMaintenance.clear(using: container.mainContext)

        #expect(
            try await repository.conversation(serverURI: developmentURI).map(\.text) == [
                pending.text
            ])
        #expect(try await repository.conversation(serverURI: productionURI).isEmpty)
        #expect(
            try await repository.pendingUtterances(serverURI: developmentURI).map(\.text)
                == [pending.text]
        )
    }

    private func writeConversation(to storeURL: URL) async throws {
        let container = try ModelContainer(
            for: ConversationItemModel.self, PendingUtteranceModel.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let repository = SwiftDataConversationRepository(modelContainer: container)
        let utterance = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Yes, please remember.",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_010_100),
            confidence: 1
        )
        try await repository.enqueue(
            utterance,
            inReplyTo: nil,
            serverURI: "https://world.example/v1"
        )
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
