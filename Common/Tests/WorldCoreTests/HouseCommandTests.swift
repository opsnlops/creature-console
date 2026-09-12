import Foundation
import Testing
import WorldCore

@Suite("Asking the house for a scene")
struct HouseCommandTests {
    private let offered = ["Normal Evening", "Movie Time", "Bedtime", "Bunnys Room Bedtime"]
    private let rule = SceneRequestRule()

    @Test("An ask names an offered scene with a word that makes it an ask")
    func recognisesAsks() {
        #expect(
            rule.scene(in: "Beaky, set the lights to normal evening", offered: offered)
                == "Normal Evening")
        #expect(rule.scene(in: "lights: Movie Time please", offered: offered) == "Movie Time")
        #expect(rule.scene(in: "switch to bedtime", offered: offered) == "Bedtime")
        #expect(rule.scene(in: "Mango, make it Movie Time!", offered: offered) == "Movie Time")
        // The longest name wins.
        #expect(
            rule.scene(in: "set the bunnys room bedtime scene", offered: offered)
                == "Bunnys Room Bedtime")
    }

    @Test("A mention is not an ask, and an unknown scene is nothing")
    func ignoresMentions() {
        #expect(rule.scene(in: "I love movie time with you all", offered: offered) == nil)
        #expect(rule.scene(in: "set the lights to disco", offered: offered) == nil)
        #expect(rule.scene(in: "", offered: offered) == nil)
        #expect(rule.scene(in: "set the lights to normal evening", offered: []) == nil)
    }

    @Test("The ingress puts the house's answer first in what the mind is told")
    func ingressCarriesTheRequest() async throws {
        let house = try EntityID(validating: "house:aprils-nest")
        let requested = try Fact(
            subjectID: house, predicate: WorldFacts.houseSceneRequested,
            value: .string("Normal Evening"),
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: Date(timeIntervalSince1970: 1_789_600_000), derivedFrom: [],
            producer: FactProducer(kind: "reducer", id: "house", version: "1"))
        let service = PersonUtteranceIngressService(
            repository: TestUtteranceRepository(),
            sink: TestPerceptSink(),
            houseCommands: FixedHouseCommands(answer: requested)
        )
        let utterance = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-house"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Beaky, set the lights to normal evening",
            modality: .typed, source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_600_000), confidence: 1)

        let result = try await service.ingest(
            utterance, context: UtteranceIngressContext(boundary: .trustedLAN))

        #expect(result.percept.worldFacts.first == requested)
    }
}

private struct FixedHouseCommands: HouseCommandRecognizing {
    let answer: Fact
    func request(in utterance: PersonUtterance) async throws -> Fact? { answer }
}

private actor TestUtteranceRepository: UtteranceIngressRepository {
    private var records: [UtteranceID: StoredUtteranceIngress] = [:]
    func ingress(for utteranceID: UtteranceID) -> StoredUtteranceIngress? { records[utteranceID] }
    func newestConversationItems(in conversationID: ConversationID, limit: Int)
        -> [ConversationItem]
    { [] }
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
