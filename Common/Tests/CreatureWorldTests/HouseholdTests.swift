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

@Suite("The house's word on a sighting")
struct HouseholdIdentificationTests {
    @Test("Home and nobody expected: a person seen is April, as a fact on the place, for a while")
    func identifiesApril() throws {
        let kitchen = try EntityID(validating: "place:kitchen")
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let seen = try WorldEventEnvelope(
            type: HouseEvents.personSeen, occurredAt: now,
            source: EventSource(
                id: try SourceID(validating: "home-assistant:kitchen"),
                kind: HouseEvents.sourceKind,
                sourceEventID: "ctx"),
            subjectIDs: [kitchen], placeID: kitchen,
            epistemic: EpistemicState(type: .observed, confidence: 1), payload: [:])
        let identified = try #require(
            try Household.identification(
                of: seen, place: kitchen, situation: HouseholdSituation(aprilHome: true), now: now))
        #expect(identified.type == GivenFactAnnouncement.eventType)
        #expect(identified.payload["subject_id"] == .string("place:kitchen"))
        #expect(identified.payload["predicate"] == .string(WorldFacts.sightingIdentified))
        #expect(identified.payload["value"] == .string("April"))
        #expect(identified.payload["valid_for_seconds"] == .number(1_800))
        #expect(identified.epistemic.type == .assumed)
        #expect(identified.causedBy == [.event(seen.eventID)])
        #expect(identified.source.id.rawValue == "world:household")
        // Away, a visitor expected, or not a person: the house says nothing.
        #expect(
            try Household.identification(
                of: seen, place: kitchen, situation: HouseholdSituation(aprilHome: false), now: now)
                == nil)
        #expect(
            try Household.identification(
                of: seen, place: kitchen,
                situation: HouseholdSituation(aprilHome: true, visitorExpected: "Tamara"), now: now)
                == nil)
        #expect(
            try Household.identification(
                of: seen, place: kitchen, situation: .unknown, now: now) == nil)
        var vehicle = seen
        vehicle.type = HouseEvents.vehicleSeen
        #expect(
            try Household.identification(
                of: vehicle, place: kitchen, situation: HouseholdSituation(aprilHome: true),
                now: now) == nil)
    }
}
