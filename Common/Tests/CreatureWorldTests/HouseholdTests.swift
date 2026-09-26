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

@Suite("A delivery is expected")
struct HouseholdDeliveryTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    /// An order as the Bridge casts it: merchant, items, status, the mail's day, and when the
    /// mail spoke.
    private func order(
        _ id: String, status: String, expected: String?, updatedAt: Date, items: [String]
    ) throws -> [Fact] {
        let subject = try EntityID(validating: id)
        func fact(_ predicate: String, _ value: WorldJSONValue) throws -> Fact {
            try Fact(
                subjectID: subject, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1),
                validFrom: updatedAt, validTo: nil, derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
        }
        var facts = [
            try fact("order.merchant", .string("Amazon")),
            try fact("order.items", .array(items.map { .string($0) })),
            try fact(WorldFacts.orderStatus, .string(status)),
            try fact("order.updated_at", .string(WorldJSON.timestamp(updatedAt))),
        ]
        if let expected { facts.append(try fact(WorldFacts.orderExpected, .string(expected))) }
        return facts
    }

    private func local(_ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(
            from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: 12))!
    }

    @Test("A shipped order the mail expects today is a delivery expected; the driver is not April")
    func shippedAndDueToday() throws {
        // The 2026-09-25 shape: shipped the night before, expected "September 25, 2026", no
        // out-for-delivery mail ever. Seen at 7:12 PM local - after midnight UTC.
        let hardware = try order(
            "order:amazon-000-0000000-0000001", status: "shipped",
            expected: "September 25, 2026", updatedAt: local(24, 19), items: ["Hardware"])
        let home = try Fact(
            subjectID: Household.april, predicate: WorldFacts.personState, value: .string("home"),
            epistemic: EpistemicState(type: .observed, confidence: 1), validFrom: local(25, 8),
            validTo: nil, derivedFrom: [],
            producer: FactProducer(kind: "test", id: "household", version: "1"))
        let situation = Household.situation(
            aprilFacts: [home], expected: [], orders: [hardware], now: local(25, 19), zone: zone)
        #expect(situation.deliveryExpected == "Amazon: Hardware")
        #expect(!situation.nobodyExpected)
        // The day before and the day after, it is not at the door.
        #expect(Household.delivery(of: hardware, now: local(24, 20), zone: zone) == nil)
        #expect(Household.delivery(of: hardware, now: local(26, 9), zone: zone) == nil)
    }

    @Test("Out for delivery this morning counts with no day; delivered and yesterday's do not")
    func outForDeliveryAndDelivered() throws {
        let out = try order(
            "order:amazon-000-0000000-0000002", status: "out_for_delivery", expected: nil,
            updatedAt: local(25, 7), items: ["Servo horns", "Zip ties"])
        #expect(
            Household.delivery(of: out, now: local(25, 14), zone: zone)
                == "Amazon: Servo horns, Zip ties")
        #expect(Household.delivery(of: out, now: local(26, 14), zone: zone) == nil)
        let delivered = try order(
            "order:amazon-000-0000000-0000003", status: "delivered",
            expected: "September 25, 2026", updatedAt: local(25, 15), items: ["Hardware"])
        #expect(Household.delivery(of: delivered, now: local(25, 16), zone: zone) == nil)
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
                of: seen, place: kitchen,
                situation: HouseholdSituation(
                    aprilHome: true, deliveryExpected: "Amazon: Hardware"),
                now: now) == nil)
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
