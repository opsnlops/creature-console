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

    @Test("Conversation survives reopening the on-disk SwiftData store")
    func conversationSurvivesApplicationRestart() async throws {
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
        let (initialItemCount, beakyItemID) = try await writeConversation(to: storeURL)

        let reopenedContainer = try ModelContainer(
            for: ConversationItemModel.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let reopenedService = SwiftDataConversationService(modelContainer: reopenedContainer)
        let restoredItems = try await reopenedService.conversation()
        #expect(restoredItems.count == initialItemCount + 2)
        #expect(
            restoredItems.suffix(2).map(\.text) == [
                "Yes, please remember.",
                "I heard you. This is where our conversation begins. 🦜",
            ])
        #expect(restoredItems[restoredItems.count - 2].inReplyToItemID == beakyItemID)
    }

    private func writeConversation(
        to storeURL: URL
    ) async throws -> (initialItemCount: Int, beakyItemID: ConversationItemID) {
        let container = try ModelContainer(
            for: ConversationItemModel.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let service = SwiftDataConversationService(modelContainer: container)
        let initialItems = try await service.conversation()
        let beakyItem = try #require(initialItems.first)

        try await service.submit(text: "Yes, please remember.", inReplyTo: beakyItem)
        return (initialItems.count, beakyItem.itemID)
    }
}
