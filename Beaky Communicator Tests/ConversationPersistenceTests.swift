import Foundation
import SwiftData
import Testing
import WorldCore

@testable import Beaky_Communicator

@MainActor
@Suite("Beaky Communicator conversation persistence", .serialized)
struct ConversationPersistenceTests {
    @Test("SwiftData model preserves the complete WorldCore conversation item")
    func modelRoundTrip() throws {
        let item = try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:persistence-test"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            authorID: EntityID(validating: "character:beaky"),
            authorKind: .character,
            text: "I will remember this.",
            createdAt: Date(timeIntervalSince1970: 1_789_010_000),
            responseID: ResponseID(validating: "response:persistence-test")
        )

        let model = try ConversationItemModel(item: item)

        #expect(try model.item == item)
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
        let restoredItems = try await reopenedRepository.conversation()
        #expect(restoredItems.map(\.text) == ["Yes, please remember."])
        #expect(restoredItems.only?.authorKind == .person)
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
        try await repository.enqueue(utterance, inReplyTo: nil)
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
