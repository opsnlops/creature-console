import Foundation
import Testing

@testable import WorldCore

/// The standing page and what the words call up beside it (#245).
@Suite("A mind's page, standing and called up")
struct KnowledgePageTests {
    private static let at = Date(timeIntervalSince1970: 1_789_500_000)

    private static func fact(_ subject: String, _ predicate: String) throws -> Fact {
        try Fact(
            subjectID: EntityID(validating: subject), predicate: predicate, value: .string("x"),
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: at,
            derivedFrom: [], producer: FactProducer(kind: "reducer", id: "test", version: "1"))
    }

    /// A world whose page has room for three: a name in the words takes two of the places,
    /// as Jesse's facts once took ten of Beaky's thirty.
    private struct Crowded: WorldKnowledgeProviding {
        let standing: [Fact]
        let named: [Fact]
        func currentFacts(about subjects: [EntityID], mentionedIn text: String?, limit: Int)
            async throws -> [Fact]
        {
            guard let text, text.contains("Jesse") else { return standing }
            // The thirty newest across every subject, then the pronouns of the page, again.
            return Array(named + standing.prefix(1)) + [named[0]]
        }
    }

    @Test("The standing page is the page without words; what the words bring sits beside it")
    func standingIsNeverDisplaced() async throws {
        let standing = [
            try Self.fact("person:april", "flight.training"),
            try Self.fact("person:april", "food.preference"),
            try Self.fact("place:workshop", "workshop.current"),
        ]
        let named = [
            try Self.fact("person:jesse", "project.deck"),
            try Self.fact("person:jesse", "visit.next"),
        ]
        let world = Crowded(standing: standing, named: named)
        let beaky = try EntityID(validating: "character:beaky")

        let page = try await world.page(about: [beaky], mentionedIn: "Is Jesse coming?", limit: 3)
        #expect(page.facts == standing + named)
        #expect(page.calledUp == named.map(\.factID))

        // No words, or only space where words would be: the standing page, nothing called up.
        let quiet = try await world.page(about: [beaky], mentionedIn: nil, limit: 3)
        #expect(quiet == KnowledgePage(facts: standing, calledUp: []))
        #expect(try await world.page(about: [beaky], mentionedIn: "", limit: 3) == quiet)
        // Words that bring nobody: the same page, still nothing called up.
        let idle = try await world.page(about: [beaky], mentionedIn: "what time is it?", limit: 3)
        #expect(idle == quiet)
    }

    private static func calledUpField(_ data: Data) throws -> WorldJSONValue? {
        guard
            case .object(let fields) = try WorldJSON.makeDecoder().decode(
                WorldJSONValue.self, from: data)
        else { return nil }
        return fields["called_up"]
    }

    @Test("called_up rides on the percept and the scene offer; a world without it sends none")
    func calledUpOnTheWire() throws {
        let jesse = try Self.fact("person:jesse", "project.deck")
        let beaky = try EntityID(validating: "character:beaky")
        let offer = SceneTurnOffer(
            sceneID: .generated(), characterID: beaky, responseID: .generated(),
            deadline: Self.at,
            trigger: SceneTrigger(
                kind: .worldEvent, eventID: .generated(), speakerID: nil, text: "The door."),
            participants: [beaky], turns: [], worldFacts: [jesse], calledUp: [jesse.factID])
        let encoded = try WorldJSON.makeEncoder().encode(offer)
        #expect(try Self.calledUpField(encoded) == .array([.string(jesse.factID.rawValue)]))
        let decoded = try WorldJSON.makeDecoder().decode(SceneTurnOffer.self, from: encoded)
        #expect(decoded.calledUp == [jesse.factID])

        // An offer from an older world has no called_up at all: nil, not empty.
        let older = SceneTurnOffer(
            sceneID: offer.sceneID, characterID: beaky, responseID: offer.responseID,
            deadline: Self.at, trigger: offer.trigger, participants: [beaky], turns: [],
            worldFacts: [jesse])
        let olderWire = try WorldJSON.makeEncoder().encode(older)
        #expect(try Self.calledUpField(olderWire) == nil)
        #expect(
            try WorldJSON.makeDecoder().decode(SceneTurnOffer.self, from: olderWire).calledUp == nil
        )

        let percept = try PersonUtterancePercept(
            characterID: beaky,
            utterance: PersonUtterance(
                conversationID: ConversationID(validating: "conversation:april-house"),
                speakerID: EntityID(validating: "person:april"), addresseeIDs: [beaky],
                text: "Is Jesse coming?", modality: .typed, source: .communicatorComposition,
                sourceID: SourceID(validating: "communicator:test"), occurredAt: Self.at,
                confidence: 1),
            priorConversationItems: [], worldFacts: [jesse], calledUp: [jesse.factID])
        let round = try WorldJSON.makeDecoder().decode(
            PersonUtterancePercept.self, from: try WorldJSON.makeEncoder().encode(percept))
        #expect(round.calledUp == [jesse.factID])
    }
}
