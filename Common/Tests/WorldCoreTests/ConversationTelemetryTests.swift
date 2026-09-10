import Foundation
import Testing

@testable import WorldCore

@Suite("Conversation OTel privacy")
struct ConversationTelemetryTests {
    @Test("OTel attributes contain causal metadata but no conversation content or credentials")
    func telemetryAttributesExcludeSensitiveValues() throws {
        let privateText = "I felt lonely when you could not hear me"
        let credential = "gateway-secret-that-must-never-be-an-attribute"
        let utterance = try PersonUtterance(
            utteranceID: UtteranceID(validating: "utterance:private-1"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: privateText,
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:april-iphone"),
            occurredAt: Date(timeIntervalSince1970: 1_789_042_000),
            confidence: 1,
            trace: W3CTraceContext(
                traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-7a9c2f8e6b31d402-01",
                baggage: "credential=\(credential)"
            )
        )
        let attributes = ConversationTelemetry.ingressAttributes(
            utterance: utterance,
            context: UtteranceIngressContext(
                boundary: .authenticatedGateway,
                principalID: utterance.speakerID
            )
        )
        let rendered = String(describing: attributes)

        #expect(
            Set(attributes.keys) == [
                "conversation.utterance.id",
                "conversation.id",
                "conversation.utterance.source",
                "conversation.utterance.modality",
                "conversation.ingress.boundary",
            ]
        )
        #expect(!rendered.contains(privateText))
        #expect(!rendered.contains(credential))
        #expect(!rendered.contains(utterance.trace?.traceparent ?? ""))
        #expect(!rendered.contains(utterance.sourceID.rawValue))
    }

    @Test("Delivery OTel attributes cannot contain Beaky's words")
    func deliveryTelemetryExcludesCharacterText() throws {
        let privateText = "This is what Beaky wants to tell April"
        let intent = try CharacterUtteranceIntent(
            responseID: ResponseID(validating: "response:private-1"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            characterID: EntityID(validating: "character:beaky"),
            recipientID: EntityID(validating: "person:april"),
            text: privateText,
            urgency: 0.5,
            createdAt: Date(timeIntervalSince1970: 1_789_042_000)
        )
        let decision = try CharacterDeliveryDecision(
            attemptID: DeliveryAttemptID(validating: "delivery-attempt:private-1"),
            responseID: intent.responseID,
            route: .communicator,
            privacyMode: .private,
            reason: .presenceUncertain,
            decidedAt: intent.createdAt,
            presence: PersonPresence(
                personID: intent.recipientID,
                state: .unknown,
                confidence: 0.3,
                observedAt: intent.createdAt.addingTimeInterval(-60),
                validUntil: intent.createdAt.addingTimeInterval(-1),
                physicallyAudible: false
            )
        )
        let attributes = ConversationTelemetry.deliveryAttributes(
            intent: intent, decision: decision)
        let rendered = String(describing: attributes)

        #expect(
            Set(attributes.keys) == [
                "conversation.delivery.attempt.id",
                "conversation.response.id",
                "conversation.id",
                "conversation.delivery.route",
                "conversation.delivery.reason",
                "conversation.delivery.privacy_mode",
            ]
        )
        #expect(!rendered.contains(privateText))
        #expect(!rendered.contains(intent.characterID.rawValue))
        #expect(!rendered.contains(intent.recipientID.rawValue))
    }
}
