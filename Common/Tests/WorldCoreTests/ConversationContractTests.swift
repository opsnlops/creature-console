import Foundation
import Testing

@testable import WorldCore

@Suite("Bidirectional conversation contracts")
struct ConversationContractTests {
    @Test("Beaky can initiate and April can answer the same conversation")
    func proactiveCharacterTurnAndPersonReplyRemainLinked() throws {
        let response = try makeCharacterIntent(inResponseTo: nil)
        let reply = try PersonUtterance(
            utteranceID: try UtteranceID(validating: "utterance:april-reply-1"),
            conversationID: response.conversationID,
            speakerID: try EntityID(validating: "person:april"),
            addresseeIDs: [response.characterID],
            inResponseToResponseID: response.responseID,
            text: "Yes, I heard you. What do you think?",
            modality: .typed,
            source: .communicatorReply,
            sourceID: try SourceID(validating: "communicator:april-iphone"),
            occurredAt: Self.now,
            confidence: 1
        )

        #expect(response.inResponseToUtteranceID == nil)
        #expect(reply.inResponseToResponseID == response.responseID)
        #expect(reply.conversationID == response.conversationID)
    }

    @Test("Reactive Beaky turns preserve the April utterance they answer")
    func reactiveCharacterTurnRemainsLinked() throws {
        let utteranceID = try UtteranceID(validating: "utterance:april-1")
        let response = try makeCharacterIntent(inResponseTo: utteranceID)
        #expect(response.inResponseToUtteranceID == utteranceID)
    }

    @Test("Conversation contracts reject blank text and contradictory origins")
    func invalidConversationShapesAreRejected() throws {
        #expect(throws: WorldContractError.emptyUtterance) {
            try PersonUtterance(
                conversationID: try ConversationID(validating: "conversation:april-beaky"),
                speakerID: try EntityID(validating: "person:april"),
                addresseeIDs: [try EntityID(validating: "character:beaky")],
                text: "   ",
                modality: .typed,
                source: .wizardMode,
                sourceID: try SourceID(validating: "wizard:mode"),
                occurredAt: Self.now,
                confidence: 1
            )
        }

        #expect(throws: WorldContractError.invalidConversationItem) {
            try ConversationItem(
                conversationID: try ConversationID(validating: "conversation:april-beaky"),
                authorID: try EntityID(validating: "person:april"),
                authorKind: .person,
                text: "This cannot have two origins",
                createdAt: Self.now,
                utteranceID: try UtteranceID(validating: "utterance:april-1"),
                responseID: try ResponseID(validating: "response:beaky-1")
            )
        }
    }

    @Test("Sensitive conversation records have deterministic size bounds")
    func conversationContentIsBounded() throws {
        let oversizedText = String(
            repeating: "🦜",
            count: ConversationContractLimits.maximumTextUnicodeScalars + 1
        )
        #expect(
            throws: WorldContractError.conversationContentTooLarge(
                maximumUnicodeScalars: ConversationContractLimits.maximumTextUnicodeScalars
            )
        ) {
            try PersonUtterance(
                conversationID: try ConversationID(validating: "conversation:april-beaky"),
                speakerID: try EntityID(validating: "person:april"),
                addresseeIDs: [try EntityID(validating: "character:beaky")],
                text: oversizedText,
                modality: .typed,
                source: .communicatorComposition,
                sourceID: try SourceID(validating: "communicator:april-mac"),
                occurredAt: Self.now,
                confidence: 1
            )
        }

        let priorItem = try ConversationItem(
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            authorID: EntityID(validating: "character:beaky"),
            authorKind: .character,
            text: "One remembered turn",
            createdAt: Self.now,
            responseID: ResponseID(validating: "response:remembered")
        )
        let utterance = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Can you hear me?",
            modality: .typed,
            source: .wizardMode,
            sourceID: SourceID(validating: "wizard:mode"),
            occurredAt: Self.now,
            confidence: 1
        )
        #expect(
            throws: WorldContractError.conversationContextTooLarge(
                maximumItems: ConversationContractLimits.maximumContextItems
            )
        ) {
            try PersonUtterancePercept(
                characterID: try EntityID(validating: "character:beaky"),
                utterance: utterance,
                priorConversationItems: Array(
                    repeating: priorItem,
                    count: ConversationContractLimits.maximumContextItems + 1
                )
            )
        }
    }

    @Test("Delivery decisions enforce route privacy")
    func deliveryRouteAndPrivacyMustAgree() throws {
        let presence = try makePresence(state: .home, physicallyAudible: true)
        #expect(throws: WorldContractError.inconsistentDeliveryDecision) {
            try CharacterDeliveryDecision(
                responseID: try ResponseID(validating: "response:beaky-1"),
                route: .physicalSpeech,
                privacyMode: .private,
                reason: .homeAndAudible,
                decidedAt: Self.now,
                presence: presence
            )
        }
    }

    private func makeCharacterIntent(
        inResponseTo utteranceID: UtteranceID?
    ) throws -> CharacterUtteranceIntent {
        try CharacterUtteranceIntent(
            responseID: try ResponseID(validating: "response:beaky-1"),
            conversationID: try ConversationID(validating: "conversation:april-beaky"),
            characterID: try EntityID(validating: "character:beaky"),
            recipientID: try EntityID(validating: "person:april"),
            inResponseToUtteranceID: utteranceID,
            text: "April, did you see what arrived?",
            urgency: 0.4,
            createdAt: Self.now
        )
    }

    private func makePresence(
        state: PersonPresenceState,
        physicallyAudible: Bool
    ) throws -> PersonPresence {
        try PersonPresence(
            personID: try EntityID(validating: "person:april"),
            state: state,
            confidence: 0.98,
            observedAt: Self.now.addingTimeInterval(-10),
            validUntil: Self.now.addingTimeInterval(60),
            physicallyAudible: physicallyAudible,
            placeID: try EntityID(validating: "place:workshop")
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_789_042_000)
}
