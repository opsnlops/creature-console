import Foundation
import Testing
import WorldCore

@testable import creature_world

@Suite("The household, as the house knows it")
struct HouseholdTests {
    private func fact(_ subject: String, _ predicate: String, _ value: WorldJSONValue) throws
        -> Fact
    {
        try Fact(
            subjectID: try EntityID(validating: subject), predicate: predicate, value: value,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: Date(), validTo: nil, derivedFrom: [],
            producer: FactProducer(kind: "test", id: "household", version: "1"))
    }

    @Test("April's presence and whoever is expected, from the facts")
    func readsPresenceAndVisitors() throws {
        let home = try fact("person:april", WorldFacts.personState, .string("home"))
        #expect(
            Household.situation(aprilFacts: [home], expected: [])
                == HouseholdSituation(aprilHome: true))
        let away = try fact("person:april", WorldFacts.personState, .string("away"))
        #expect(
            Household.situation(aprilFacts: [away], expected: [])
                == HouseholdSituation(aprilHome: false))
        // No presence fact at all: the house does not know, and says nothing.
        #expect(
            Household.situation(aprilFacts: [], expected: []) == HouseholdSituation(aprilHome: nil)
        )
        // Expected on the house (an appointment from the mail) and on a person (the calendar).
        let cleaners = try fact(
            "house:aprils-nest", WorldFacts.visitorExpected,
            .string("Quality Cleaning for cleaning, Wednesday"))
        let jesse = try fact(
            "person:jesse", WorldFacts.visitorExpected,
            .string("this afternoon, to look at the deck"))
        #expect(
            Household.situation(aprilFacts: [home], expected: [cleaners, jesse]).visitorExpected
                == "Quality Cleaning for cleaning, Wednesday; Jesse, this afternoon, to look at the deck"
        )
    }
}
