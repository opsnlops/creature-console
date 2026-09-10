import Foundation
import WorldCore

protocol CommunicatorConversationService: Sendable {
    func conversation() async throws -> [ConversationItem]
    func submit(text: String, inReplyTo item: ConversationItem?) async throws
}

actor PreviewConversationService: CommunicatorConversationService {
    private let conversationID: ConversationID
    private let aprilID: EntityID
    private let beakyID: EntityID
    private let sourceID: SourceID
    private var items: [ConversationItem]

    init() throws {
        conversationID = try ConversationID(validating: "conversation:april-beaky")
        aprilID = try EntityID(validating: "person:april")
        beakyID = try EntityID(validating: "character:beaky")
        sourceID = try SourceID(validating: "communicator:preview")
        items = Self.previewItems(
            conversationID: conversationID,
            aprilID: aprilID,
            beakyID: beakyID
        )
    }

    static func make() -> any CommunicatorConversationService {
        do {
            return try PreviewConversationService()
        } catch {
            return UnavailablePreviewConversationService()
        }
    }

    func conversation() -> [ConversationItem] {
        items
    }

    func submit(text: String, inReplyTo item: ConversationItem?) throws {
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
        items.append(aprilItem)

        let beakyReply = try ConversationItem(
            conversationID: conversationID,
            authorID: beakyID,
            authorKind: .character,
            text: "I heard you. This is where our conversation begins. 🦜",
            createdAt: now.addingTimeInterval(1),
            inReplyToItemID: aprilItem.itemID,
            responseID: .generated()
        )
        items.append(beakyReply)
    }

    private static func previewItems(
        conversationID: ConversationID,
        aprilID: EntityID,
        beakyID: EntityID
    ) -> [ConversationItem] {
        let now = Date()
        return [
            try? ConversationItem(
                conversationID: conversationID,
                authorID: beakyID,
                authorKind: .character,
                text: "April? I have been saying things all day and wondering what you thought.",
                createdAt: now.addingTimeInterval(-120),
                responseID: .generated()
            ),
            try? ConversationItem(
                conversationID: conversationID,
                authorID: aprilID,
                authorKind: .person,
                text: "I am here now, Beaky. I can finally answer you.",
                createdAt: now.addingTimeInterval(-60),
                inReplyToItemID: nil,
                utteranceID: .generated()
            ),
        ].compactMap { $0 }
    }
}

private enum PreviewConversationError: Error {
    case invalidConfiguration
}

private actor UnavailablePreviewConversationService: CommunicatorConversationService {
    func conversation() throws -> [ConversationItem] {
        throw PreviewConversationError.invalidConfiguration
    }

    func submit(text: String, inReplyTo item: ConversationItem?) throws {
        throw PreviewConversationError.invalidConfiguration
    }
}
