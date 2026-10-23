import Foundation
import Logging
import MongoKitten
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// About one meter of latitude, in degrees.
private let meter = 1 / 111_195.0

/// Where April is without being told (#248, slice 3): the rule's confidence, apart from the
/// store.
@Suite("How sure the world is that April is at a place")
struct PlaceConfidenceTests {
    @Test("Sure at the pin, less so toward the edge of its reach, never beyond either")
    func confidence() {
        #expect(PlaceInferenceRule.confidence(meters: 0, reach: 85) == 0.95)
        #expect(PlaceInferenceRule.confidence(meters: 85, reach: 85) == 0.7)
        #expect(abs(PlaceInferenceRule.confidence(meters: 42.5, reach: 85) - 0.825) < 1e-9)
        #expect(PlaceInferenceRule.confidence(meters: 200, reach: 85) == 0.7)
        #expect(PlaceInferenceRule.confidence(meters: 10, reach: 0) == 0.95)
    }

    @Test("Coming home ends a place the world guessed, as it ends one April told")
    func homeEndsAGuess() throws {
        let april = try EntityID(validating: "person:april")
        let producer = FactProducer(kind: "reducer", id: "house", version: "1")
        func place(_ type: EpistemicType) throws -> Fact {
            try Fact(
                subjectID: april, predicate: WorldFacts.presencePlace,
                value: .string("place:gym"), epistemic: EpistemicState(type: type, confidence: 0.9),
                validFrom: Date(), derivedFrom: [], producer: producer)
        }
        let arrival = try HouseReducer().reduce(
            try WorldEventEnvelope(
                type: HouseEvents.personArrived, occurredAt: Date(),
                source: EventSource(
                    id: try SourceID(validating: "home-assistant:person-april"),
                    kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                subjectIDs: [april], epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: ["entity_id": .string("person.april"), "state": .string("home")]))
        let retraction = try #require(arrival.retractions.first)
        #expect(retraction.covers(try place(.reported)))
        #expect(retraction.covers(try place(.inferred)))
        #expect(!retraction.covers(try place(.assumed)))
        // Other retractions end only what was told, as before.
        var told = retraction
        told.bases = [.reported]
        #expect(!told.covers(try place(.inferred)))
    }
}

/// The rule and its query against the store. Each run's places sit at a point of its own in
/// Kansas, made up and never April's (the repository is public): the shared test database holds
/// other runs' pins, and a place is found near anything within its reach.
@Suite(
    "April's phone at a place she taught, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct PlaceInferenceMongoTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Harness {
        let persistence: MongoWorldPersistence
        let world: World
        let rule: PlaceInferenceRule
        let april: EntityID
        let dentist: EntityID
        let gym: EntityID
        let latitude: Double
        let longitude: Double
        let now: Date

        /// A pin, `north` meters from this run's point.
        func pin(_ place: EntityID, north: Double = 0, radius: Double = 75) async throws {
            let pin = PlacePin(
                latitude: latitude + north * meter, longitude: longitude, radius: radius,
                fixes: 1, taughtBy: "mind:beaky")
            try await save(
                place, WorldFacts.placeGeo, pin.value, .inferred,
                at: now.addingTimeInterval(-86_400))
        }

        func save(
            _ subject: EntityID, _ predicate: String, _ value: WorldJSONValue,
            _ type: EpistemicType, at: Date
        ) async throws {
            let fact = try Fact(
                subjectID: subject, predicate: predicate, value: value,
                epistemic: EpistemicState(type: type, confidence: 1), validFrom: at,
                derivedFrom: [], producer: FactProducer(kind: "test", id: "places", version: "1"))
            try await persistence.facts.save(fact)
            try await persistence.facts.supersede(by: fact)
        }

        /// The house's event: her phone `north` meters from this run's point, `minutes` on.
        @discardableResult
        func fix(north: Double, accuracy: Double = 10, minutes: Double) async throws
            -> WorldEventEnvelope
        {
            let event = try WorldEventEnvelope(
                type: HouseEvents.personLocated, occurredAt: now.addingTimeInterval(minutes * 60),
                source: EventSource(
                    id: try SourceID(validating: "home-assistant:person-april"),
                    kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                subjectIDs: [april], epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: [
                    "entity_id": .string("person.april"),
                    "latitude": .number(latitude + north * meter), "longitude": .number(longitude),
                    "accuracy_m": .number(accuracy),
                ])
            _ = try await world.accept(event)
            try await rule.heard(event)
            return event
        }

        func house(_ type: WorldEventType, minutes: Double) async throws {
            _ = try await world.accept(
                try WorldEventEnvelope(
                    type: type, occurredAt: now.addingTimeInterval(minutes * 60),
                    source: EventSource(
                        id: try SourceID(validating: "home-assistant:person-april"),
                        kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                    subjectIDs: [april],
                    epistemic: EpistemicState(type: .observed, confidence: 1),
                    payload: ["entity_id": .string("person.april")]))
        }

        /// Where the world has her, `minutes` on.
        func place(minutes: Double) async throws -> Fact? {
            try await persistence.facts.currentFacts(
                subjectID: april, at: now.addingTimeInterval(minutes * 60 + 0.5)
            )
            .first { $0.predicate == WorldFacts.presencePlace && $0.value != .null }
        }
    }

    private func harness() async throws -> Harness {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "place-inference-tests"))
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [GivenFactReducer(), HouseReducer()], clock: ManualWorldClock(now: now))
        let suffix = UUID().uuidString.lowercased()
        let h = Harness(
            persistence: persistence, world: world,
            rule: PlaceInferenceRule(facts: persistence.facts) { _ = try await world.accept($0) },
            april: try EntityID(validating: "person:april-\(suffix)"),
            dentist: try EntityID(validating: "place:dentist-\(suffix)"),
            gym: try EntityID(validating: "place:gym-\(suffix)"),
            latitude: Double.random(in: 37.5...39.5), longitude: Double.random(in: -101...(-98)),
            now: now)
        // She is out: the house saw her leave.
        try await h.house(HouseEvents.personLeft, minutes: -30)
        return h
    }

    @Test("Only a place whose radius and the fix's doubt reach her is near, nearest first")
    func placesNear() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        try await h.pin(h.dentist)
        try await h.pin(h.gym, north: 300, radius: 300)
        func near(_ north: Double, slack: Double = 10) async throws -> [EntityID] {
            try await h.persistence.facts.placesNear(
                latitude: h.latitude + north * meter, longitude: h.longitude, slack: slack,
                at: h.now
            ).map(\.fact.subjectID).filter { [h.dentist, h.gym].contains($0) }
        }
        // At the dentist, inside the gym's wide reach too: the nearer first.
        #expect(try await near(20) == [h.dentist, h.gym])
        #expect(try await near(280) == [h.gym])
        // 80 m from the dentist: out of its 75 m, but not of 75 m and a fix 10 m unsure.
        #expect(try await near(-80) == [h.dentist])
        #expect(try await near(-80, slack: 0) == [])
        #expect(try await near(-600) == [])
        let first = try #require(
            try await h.persistence.facts.placesNear(
                latitude: h.latitude + 20 * meter, longitude: h.longitude, slack: 10, at: h.now
            ).first { $0.fact.subjectID == h.dentist })
        #expect(abs(first.meters - 20) < 0.5)

        // Moved, the dentist's old pin is no longer anywhere; the gym's wide reach still is.
        try await h.save(
            h.dentist, WorldFacts.placeGeo,
            PlacePin(
                latitude: h.latitude + 2_000 * meter, longitude: h.longitude, radius: 75, fixes: 1,
                taughtBy: "mind:beaky"
            ).value, .reported, at: h.now.addingTimeInterval(-60))
        #expect(try await near(0) == [h.gym])
        #expect(try await near(2_000) == [h.dentist])
    }

    @Test("At a taught place she is there, inferred, from when she arrived until she leaves")
    func arrivesAndLeaves() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        try await h.pin(h.dentist)
        try await h.pin(h.gym, north: 1_000)

        // On the road, far from either: nothing.
        try await h.fix(north: -3_000, minutes: 0)
        #expect(try await h.place(minutes: 0) == nil)

        // Parked 40 m from the dentist's pin.
        let arrival = try await h.fix(north: 40, minutes: 5)
        let at = try #require(try await h.place(minutes: 5))
        #expect(at.value == .string(h.dentist.rawValue))
        #expect(at.epistemic.type == .inferred)
        #expect(at.epistemic.confidence > 0.7 && at.epistemic.confidence < 0.95)
        #expect(at.origin?.rawValue == "world:places")
        #expect(at.validFrom == arrival.occurredAt)
        #expect(at.validTo == nil)

        // Another fix inside, an hour on: still there, since when she arrived.
        try await h.fix(north: 10, minutes: 65)
        #expect(try await h.place(minutes: 65)?.factID == at.factID)

        // Driving off, out of its reach: she has left.
        try await h.fix(north: 400, minutes: 70)
        #expect(try await h.place(minutes: 70) == nil)

        // At the gym, then home: the house ends it.
        try await h.fix(north: 1_010, minutes: 80)
        #expect(try await h.place(minutes: 80)?.value == .string(h.gym.rawValue))
        try await h.house(HouseEvents.personArrived, minutes: 150)
        #expect(try await h.place(minutes: 150) == nil)

        // At home, a fix inside a place (the house's own point) says nothing.
        try await h.pin(h.dentist, north: 5_000)
        try await h.fix(north: 5_000, minutes: 160)
        #expect(try await h.place(minutes: 160) == nil)
    }

    @Test("A place she told a bird ends when a fix shows her out of it, unless it has no pin")
    func toldPlaces() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        try await h.pin(h.dentist)

        // "I'm at the dentist", kept by a bird; the fix at the dentist changes nothing.
        try await h.save(
            h.april, WorldFacts.presencePlace, .string(h.dentist.rawValue), .reported,
            at: h.now)
        let told = try #require(try await h.place(minutes: 0))
        try await h.fix(north: 10, minutes: 5)
        #expect(try await h.place(minutes: 5)?.factID == told.factID)
        // Out of its reach: she has left.
        try await h.fix(north: 500, minutes: 10)
        #expect(try await h.place(minutes: 10) == nil)

        // "I'm at Jessie's", with no pin: no point says she has left.
        let jessies = try EntityID(validating: "place:jessies-\(UUID().uuidString.lowercased())")
        try await h.save(
            h.april, WorldFacts.presencePlace, .string(jessies.rawValue), .reported,
            at: h.now.addingTimeInterval(15 * 60))
        try await h.fix(north: 3_000, minutes: 20)
        #expect(try await h.place(minutes: 20)?.value == .string(jessies.rawValue))
    }

    @Test("A vague fix places no one, and ends nothing")
    func vagueFix() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        try await h.pin(h.dentist)
        try await h.fix(north: 0, accuracy: 150, minutes: 0)
        #expect(try await h.place(minutes: 0) == nil)
        try await h.fix(north: 0, minutes: 5)
        try await h.fix(north: 900, accuracy: 150, minutes: 10)
        #expect(try await h.place(minutes: 10)?.value == .string(h.dentist.rawValue))
    }

    @Test("The migration gives the pins saved before it their point")
    func backfill() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        try await h.pin(h.dentist)
        let collection = h.persistence.database[MongoWorldCollection.facts]
        _ = try await collection.updateMany(
            where: ["subject_id": h.dentist.rawValue],
            to: ["$unset": [FactRepository.geoField: ""] as Document])
        #expect(
            try await h.persistence.facts.placesNear(
                latitude: h.latitude, longitude: h.longitude, slack: 10, at: h.now
            ).allSatisfy { $0.fact.subjectID != h.dentist })
        #expect(try await h.persistence.facts.backfillGeo() >= 1)
        #expect(
            try await h.persistence.facts.placesNear(
                latitude: h.latitude, longitude: h.longitude, slack: 10, at: h.now
            ).contains { $0.fact.subjectID == h.dentist })
    }
}
