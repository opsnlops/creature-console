import Foundation
import SwiftData
import WorldCore

protocol CommunicatorConversationService: Sendable {
    func conversation() async throws -> [ConversationItem]
    func submit(text: String, inReplyTo item: ConversationItem?) async throws
}

@ModelActor
actor SwiftDataConversationService: CommunicatorConversationService {
    func conversation() throws -> [ConversationItem] {
        var models = try fetchConversationModels()
        if models.isEmpty {
            try seedPreviewConversation()
            models = try fetchConversationModels()
        }
        return try models.map { try $0.item }
    }

    func submit(text: String, inReplyTo item: ConversationItem?) throws {
        let conversationID = try ConversationID(validating: "conversation:april-beaky")
        let aprilID = try EntityID(validating: "person:april")
        let beakyID = try EntityID(validating: "character:beaky")
        let sourceID = try SourceID(validating: "communicator:preview")
        let now = Date()
        let utterance = try PersonUtterance(
            conversationID: conversationID,
            speakerID: aprilID,
            addresseeIDs: [beakyID],
            inResponseToResponseID: item?.responseID,
            text: text,
            modality: .typed,
            source: item == nil ? .communicatorComposition : .communicatorReply,
            sourceID: sourceID,
            occurredAt: now,
            confidence: 1
        )
        let aprilItem = try ConversationItem(
            conversationID: conversationID,
            authorID: aprilID,
            authorKind: .person,
            text: utterance.text,
            createdAt: now,
            inReplyToItemID: item?.itemID,
            utteranceID: utterance.utteranceID
        )

        let beakyReply = try ConversationItem(
            conversationID: conversationID,
            authorID: beakyID,
            authorKind: .character,
            text: "I heard you. This is where our conversation begins. 🦜",
            createdAt: now.addingTimeInterval(1),
            inReplyToItemID: aprilItem.itemID,
            responseID: .generated()
        )

        modelContext.insert(try ConversationItemModel(item: aprilItem))
        modelContext.insert(try ConversationItemModel(item: beakyReply))
        try modelContext.save()
    }

    private func fetchConversationModels() throws -> [ConversationItemModel] {
        let descriptor = FetchDescriptor<ConversationItemModel>(
            sortBy: [
                SortDescriptor(\ConversationItemModel.createdAt),
                SortDescriptor(\ConversationItemModel.id),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func seedPreviewConversation() throws {
        let conversationID = try ConversationID(validating: "conversation:april-beaky")
        let aprilID = try EntityID(validating: "person:april")
        let beakyID = try EntityID(validating: "character:beaky")
        let firstItemID = try ConversationItemID(validating: "conversation-item:preview-beaky-1")
        let secondItemID = try ConversationItemID(validating: "conversation-item:preview-april-1")
        let items = [
            try ConversationItem(
                itemID: firstItemID,
                conversationID: conversationID,
                authorID: beakyID,
                authorKind: .character,
                text: "April? I have been saying things all day and wondering what you thought.",
                createdAt: Date(timeIntervalSince1970: 1_789_001_000),
                responseID: ResponseID(validating: "response:preview-beaky-1")
            ),
            try ConversationItem(
                itemID: secondItemID,
                conversationID: conversationID,
                authorID: aprilID,
                authorKind: .person,
                text: "I am here now, Beaky. I can finally answer you.",
                createdAt: Date(timeIntervalSince1970: 1_789_001_060),
                inReplyToItemID: firstItemID,
                utteranceID: UtteranceID(validating: "utterance:preview-april-1")
            ),
        ]

        for item in items {
            modelContext.insert(try ConversationItemModel(item: item))
        }
        try modelContext.save()
    }
}
