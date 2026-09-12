import Foundation
import Testing
import WorldCore

@Suite("Addressing: who April is talking to")
struct AddressingTests {
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")
    private let kenny = try! EntityID(validating: "character:kenny")
    private var present: [String: EntityID] { ["beaky": beaky, "mango": mango, "kenny": kenny] }
    private var rule: LeadAddresseeRule { LeadAddresseeRule(lead: beaky) }

    @Test("A character named at the start gets the message")
    func namedCharacterIsAddressed() {
        #expect(rule.addressee(in: "Mango, what is in the box?", present: present) == mango)
        #expect(rule.addressee(in: "hey kenny what's up", present: present) == kenny)
        #expect(rule.addressee(in: "@Mango are you there", present: present) == mango)
        #expect(rule.addressee(in: "Okay Mango. Tell me.", present: present) == mango)
        #expect(rule.addressee(in: "MANGO!", present: present) == mango)
    }

    @Test("Everything else goes to the lead, including a name mentioned later or not present")
    func unaddressedGoesToTheLead() {
        #expect(
            rule.addressee(in: "What do you all think of the package?", present: present) == beaky)
        #expect(rule.addressee(in: "I think Mango is right.", present: present) == beaky)
        #expect(rule.addressee(in: "Caroll, are you there?", present: present) == beaky)
        #expect(rule.addressee(in: "", present: present) == beaky)
        #expect(rule.addressee(in: "Mango", present: [:]) == beaky)
    }

    @Test("The ingress asks the resolver, not the sender, who the words are for")
    func ingressUsesTheResolver() async throws {
        let repository = TestUtteranceRepository()
        let sink = TestPerceptSink()
        let service = PersonUtteranceIngressService(
            repository: repository,
            sink: sink,
            addresseeResolver: FixedResolver(answer: mango)
        )
        let utterance = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [beaky],
            text: "Mango, what is in the box?",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_500_000),
            confidence: 1
        )

        let result = try await service.ingest(
            utterance, context: UtteranceIngressContext(boundary: .trustedLAN))

        #expect(result.percept.characterID == mango)
        #expect(result.percept.utterance.addresseeIDs == [beaky])
    }
}

private struct FixedResolver: AddresseeResolving {
    let answer: EntityID
    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> EntityID {
        answer
    }
}

private actor TestUtteranceRepository: UtteranceIngressRepository {
    private var records: [UtteranceID: StoredUtteranceIngress] = [:]

    func ingress(for utteranceID: UtteranceID) -> StoredUtteranceIngress? { records[utteranceID] }
    func newestConversationItems(in conversationID: ConversationID, limit: Int)
        -> [ConversationItem]
    {
        []
    }
    func prepare(_ ingress: StoredUtteranceIngress) -> StoredUtteranceIngress {
        records[ingress.percept.utterance.utteranceID] = ingress
        return ingress
    }
    func markPerceptSubmitted(utteranceID: UtteranceID) {
        records[utteranceID]?.progress = .perceptSubmitted
    }
}

private struct TestPerceptSink: PersonUtterancePerceptSink {
    func submit(_ percept: PersonUtterancePercept) async throws -> UtterancePerceptAcceptance {
        .accepted
    }
}
