import Foundation
import Testing

@testable import WorldCore

@Suite("World identifiers")
struct IdentifierTests {
    @Test("Generated event IDs are canonical lowercase UUIDs", arguments: 1...100)
    func generatedEventIDsAreCanonical(iteration _: Int) throws {
        let eventID = EventID.generated()
        #expect(eventID.rawValue == eventID.rawValue.lowercased())
        #expect(eventID.rawValue.count == 36)
        #expect(UUID(uuidString: eventID.rawValue) != nil)
    }

    @Test("Uppercase event IDs normalize before use")
    func uppercaseEventIDNormalizes() throws {
        let input = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
        let eventID = try EventID(validating: input)
        #expect(eventID.rawValue == input.lowercased())
    }

    @Test("Non-hyphenated UUID input is rejected")
    func noncanonicalEventIDIsRejected() {
        #expect(throws: WorldIdentifierError.self) {
            try EventID(validating: "3f2504e04f8941d39a0c0305e82c3301")
        }
    }

    @Test("Namespaced IDs preserve valid stable identifiers")
    func namespacedIDsValidate() throws {
        let entityID = try EntityID(validating: "person:april")
        let orderID = try EntityID(validating: "order:acme-hardware:ah-48291")
        #expect(entityID.rawValue == "person:april")
        #expect(orderID.rawValue == "order:acme-hardware:ah-48291")
    }

    @Test("Namespaced IDs reject uppercase and whitespace")
    func noncanonicalNamespacedIDsAreRejected() {
        #expect(throws: WorldIdentifierError.self) {
            try EntityID(validating: "Person:april")
        }
        #expect(throws: WorldIdentifierError.self) {
            try EntityID(validating: "person:April White")
        }
    }

    @Test("Fixed-domain IDs reject the wrong namespace")
    func fixedNamespaceIsEnforced() {
        #expect(throws: WorldIdentifierError.self) {
            try FactID(validating: "timer:calendar-event-123:departure-due")
        }
    }

    @Test("Conversation pipeline IDs have independent stable namespaces")
    func conversationPipelineNamespacesAreIndependent() throws {
        #expect(ConversationID.generated().rawValue.hasPrefix("conversation:"))
        #expect(ConversationItemID.generated().rawValue.hasPrefix("conversation-item:"))
        #expect(UtteranceID.generated().rawValue.hasPrefix("utterance:"))
        #expect(ResponseID.generated().rawValue.hasPrefix("response:"))
        #expect(DeliveryAttemptID.generated().rawValue.hasPrefix("delivery-attempt:"))

        #expect(throws: WorldIdentifierError.self) {
            try UtteranceID(validating: "response:beaky-1")
        }
    }
}
