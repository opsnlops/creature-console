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

    @Test("A character named at the start answers first, and the room may join")
    func namedCharacterAnswersFirst() {
        let toMango = Addressee(characterID: mango, alone: false)
        #expect(rule.addressee(in: "Mango, what is in the box?", present: present) == toMango)
        #expect(
            rule.addressee(in: "hey kenny what's up", present: present)
                == Addressee(characterID: kenny, alone: false))
        #expect(rule.addressee(in: "Okay Mango. Tell me.", present: present) == toMango)
        #expect(rule.addressee(in: "MANGO!", present: present) == toMango)
        // Calling Beaky's name puts her first; the flock may still chime in.
        #expect(
            rule.addressee(in: "Beaky, I love you", present: present)
                == Addressee(characterID: beaky, alone: false))
    }

    @Test("An @-name is a whisper: that character alone")
    func whisperedCharacterIsAlone() {
        #expect(
            rule.addressee(in: "@Mango are you there", present: present)
                == Addressee(characterID: mango, alone: true))
        #expect(
            rule.addressee(in: "hey @beaky, how was your day?", present: present)
                == Addressee(characterID: beaky, alone: true))
        // An @ for someone who is not here is just a remark to the room.
        #expect(
            rule.addressee(in: "@caroll are you there?", present: present)
                == Addressee(characterID: beaky, alone: false))
    }

    @Test("Everything else goes to the lead, including a name mentioned later or not present")
    func unaddressedGoesToTheLead() {
        let room = Addressee(characterID: beaky, alone: false)
        #expect(
            rule.addressee(in: "What do you all think of the package?", present: present) == room)
        #expect(rule.addressee(in: "I think Mango is right.", present: present) == room)
        #expect(rule.addressee(in: "Caroll, are you there?", present: present) == room)
        #expect(rule.addressee(in: "", present: present) == room)
        #expect(rule.addressee(in: "Mango", present: [:]) == room)
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

    @Test("The percept carries what the world knows about the character and the speaker")
    func ingressGathersWorldFacts() async throws {
        let april = try EntityID(validating: "person:april")
        let knowledge = RecordingKnowledge(
            facts: [
                try Fact(
                    subjectID: april, predicate: "presence.state", value: .string("home"),
                    epistemic: EpistemicState(type: .assumed, confidence: 0.9),
                    validFrom: Date(timeIntervalSince1970: 1_789_500_000), derivedFrom: [],
                    producer: FactProducer(kind: "test", id: "test", version: "1"))
            ])
        let service = PersonUtteranceIngressService(
            repository: TestUtteranceRepository(),
            sink: TestPerceptSink(),
            knowledge: knowledge
        )
        let utterance = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-house"),
            speakerID: april,
            addresseeIDs: [beaky],
            text: "Is anyone there?",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_500_000),
            confidence: 1
        )

        let result = try await service.ingest(
            utterance, context: UtteranceIngressContext(boundary: .trustedLAN))

        #expect(result.percept.worldFacts == knowledge.facts)
        #expect(await knowledge.requests == [[beaky, april]])
        #expect(await knowledge.limits == [WorldKnowledgeLimits.maximumFacts])
        // The facts ride the wire under their own key, and an older world without them decodes.
        let encoded = try WorldJSON.makeEncoder().encode(result.percept)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect((json["world_facts"] as? [Any])?.count == 1)
        var stripped = json
        stripped["world_facts"] = nil
        let decoded = try WorldJSON.makeDecoder().decode(
            PersonUtterancePercept.self, from: JSONSerialization.data(withJSONObject: stripped))
        #expect(decoded.worldFacts.isEmpty)
    }
}

private actor RecordingKnowledge: WorldKnowledgeProviding {
    let facts: [Fact]
    private(set) var requests: [[EntityID]] = []
    private(set) var limits: [Int] = []

    init(facts: [Fact]) {
        self.facts = facts
    }

    func currentFacts(about subjects: [EntityID], limit: Int) -> [Fact] {
        requests.append(subjects)
        limits.append(limit)
        return facts
    }
}

private struct FixedResolver: AddresseeResolving {
    let answer: EntityID
    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> Addressee {
        Addressee(characterID: answer, alone: true)
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
