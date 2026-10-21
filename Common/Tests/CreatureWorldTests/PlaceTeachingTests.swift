import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// Made-up points in the middle of Kansas: never April's (the repository is public).
private let latitude = 40.0
private let longitude = -100.0
/// About thirty meters of latitude.
private let thirtyMeters = 30 / 111_195.0

/// April teaches the birds her places (#248, slice 2): the pin's arithmetic.
@Suite("A taught place's pin")
struct PlacePinTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func fix(_ north: Double = 0, accuracy: Double = 20) -> PhoneFix {
        PhoneFix(
            latitude: latitude + north, longitude: longitude, accuracy: accuracy, at: at)
    }

    @Test("Taught once: where her phone is, reaching 75 m or as far as the fix is unsure")
    func firstTeaching() {
        let pin = PlacePin.taught(nil, at: fix(), by: "mind:beaky")
        #expect(
            pin
                == PlacePin(
                    latitude: latitude, longitude: longitude, radius: 75, fixes: 1,
                    taughtBy: "mind:beaky"))
        #expect(PlacePin.taught(nil, at: fix(accuracy: 90), by: "mind:beaky").radius == 90)
    }

    @Test("Taught again nearby: the mean of the fixes, reaching where the old circle was")
    func taughtAgain() {
        let first = PlacePin.taught(nil, at: fix(), by: "mind:beaky")
        let second = PlacePin.taught(first, at: fix(thirtyMeters), by: "mind:mango")
        #expect(second.fixes == 2)
        #expect(abs(second.latitude - (latitude + thirtyMeters / 2)) < 1e-9)
        // The old 75 m circle, shifted about 15 m: the reach covers it.
        #expect(second.radius > 89 && second.radius < 91)
        #expect(second.taughtBy == "mind:mango")
    }

    @Test("Taught a kilometre away, the place has moved: pinned afresh")
    func moved() {
        let first = PlacePin.taught(nil, at: fix(), by: "mind:beaky")
        let moved = PlacePin.taught(first, at: fix(2_000 / 111_195.0), by: "mind:beaky")
        #expect(moved.fixes == 1)
        #expect(moved.latitude == latitude + 2_000 / 111_195.0)
        #expect(moved.radius == 75)
    }

    @Test("A place never reaches more than 500 m")
    func capped() {
        let wide = PlacePin(
            latitude: latitude, longitude: longitude, radius: 490, fixes: 1,
            taughtBy: "mind:beaky")
        #expect(PlacePin.taught(wide, at: fix(800 / 111_195.0), by: "mind:beaky").radius == 500)
    }

    @Test("The pin is a GeoJSON point, longitude first, and reads back")
    func geoJSON() throws {
        let pin = PlacePin.taught(nil, at: fix(), by: "mind:beaky")
        guard case .object(let fields) = pin.value else {
            Issue.record("not an object")
            return
        }
        #expect(fields["type"] == .string("Point"))
        #expect(fields["coordinates"] == .array([.number(longitude), .number(latitude)]))
        #expect(PlacePin(pin.value) == pin)
        #expect(abs(PlacePin.distance(40, -100, 41, -100) - 111_195) < 1)
        // The world's alone: never on a page, in a tool, in the glossary, or kept by a mind.
        #expect(WorldKnowledgeLimits.worldOnlyPredicates.contains(WorldFacts.placeGeo))
    }
}

/// The rule against the store: a bird keeping where April is pins the place where her phone is.
@Suite(
    "Places April teaches, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct PlaceTeachingMongoTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Harness {
        let persistence: MongoWorldPersistence
        let world: World
        let rule: PlaceTeachingRule
        let april: EntityID
        let dentist: EntityID
        let now: Date

        /// What the house knows of her: a fix `minutesAgo`, and home or away.
        func phone(
            north: Double = 0, accuracy: Double = 20, minutesAgo: Double = 5,
            state: PersonPresenceState = .away
        ) async throws {
            try await persistence.facts.save(
                try Fact(
                    subjectID: april, predicate: WorldFacts.locationGPS,
                    value: .object([
                        "latitude": .number(latitude + north), "longitude": .number(longitude),
                        "accuracy_m": .number(accuracy),
                    ]),
                    epistemic: EpistemicState(type: .observed, confidence: 1),
                    validFrom: now.addingTimeInterval(-minutesAgo * 60), derivedFrom: [],
                    producer: FactProducer(kind: "presence", id: "house", version: "1")))
            try await persistence.facts.save(
                try Fact(
                    subjectID: april, predicate: WorldFacts.personState,
                    value: .string(state.rawValue),
                    epistemic: EpistemicState(type: .observed, confidence: 1),
                    validFrom: now.addingTimeInterval(-3_600), derivedFrom: [],
                    producer: FactProducer(kind: "presence", id: "house", version: "1")))
        }

        /// A bird keeping her word, as the world hears it.
        func taught(
            _ value: String, by source: String = "mind:beaky", kind: String = "mind",
            at: Date? = nil
        ) async throws {
            let event = try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType, occurredAt: at ?? now,
                source: EventSource(
                    id: SourceID(validating: source), kind: kind,
                    sourceEventID: UUID().uuidString),
                subjectIDs: [april],
                epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: [
                    "subject_id": .string(april.rawValue),
                    "predicate": .string(WorldFacts.presencePlace), "value": .string(value),
                    "valid_for_seconds": .number(7_200),
                ])
            _ = try await world.accept(event)
            try await rule.heard(event)
        }

        func pin(at: Date? = nil) async throws -> PlacePin? {
            try await persistence.facts.currentFacts(subjectID: dentist, at: at ?? now)
                .first { $0.predicate == WorldFacts.placeGeo }
                .flatMap { PlacePin($0.value) }
        }
    }

    private func harness() async throws -> Harness {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "place-tests"))
        let clock = ManualWorldClock(now: now)
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [GivenFactReducer()], clock: clock)
        let suffix = UUID().uuidString.lowercased()
        return Harness(
            persistence: persistence, world: world,
            rule: PlaceTeachingRule(facts: persistence.facts) { _ = try await world.accept($0) },
            april: try EntityID(validating: "person:april-\(suffix)"),
            dentist: try EntityID(validating: "place:dentist-\(suffix)"), now: now)
    }

    @Test("\"I'm at the dentist\", away with a fresh fix: the dentist is pinned where she is")
    func pinsWhereSheIs() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        try await h.phone()
        try await h.taught(h.dentist.rawValue)
        let pin = try #require(try await h.pin())
        #expect(pin.latitude == latitude && pin.longitude == longitude)
        #expect(pin.radius == 75 && pin.fixes == 1 && pin.taughtBy == "mind:beaky")
        let fact = try #require(
            try await h.persistence.facts.currentFacts(subjectID: h.dentist, at: h.now)
                .first { $0.predicate == WorldFacts.placeGeo })
        #expect(fact.epistemic.type == .inferred)
        #expect(fact.origin?.rawValue == "world:places")
        #expect(fact.validTo == nil)

        // Taught again a little later, thirty meters on: the mean, with two fixes.
        let later = h.now.addingTimeInterval(600)
        try await h.persistence.facts.save(
            try Fact(
                subjectID: h.april, predicate: WorldFacts.locationGPS,
                value: .object([
                    "latitude": .number(latitude + thirtyMeters),
                    "longitude": .number(longitude), "accuracy_m": .number(20),
                ]),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: later.addingTimeInterval(-60), derivedFrom: [],
                producer: FactProducer(kind: "presence", id: "house", version: "1")))
        try await h.taught(h.dentist.rawValue, by: "mind:mango", at: later)
        let again = try #require(try await h.pin(at: later))
        #expect(again.fixes == 2)
        #expect(again.taughtBy == "mind:mango")
    }

    @Test("Nothing is pinned from a stale or vague fix, at home, or from a word that is no place")
    func pinsNothingUnsure() async throws {
        for (setup, value, source) in [
            ((accuracy: 20.0, minutesAgo: 20.0, state: PersonPresenceState.away), "", "mind"),
            ((accuracy: 150.0, minutesAgo: 5.0, state: .away), "", "mind"),
            ((accuracy: 20.0, minutesAgo: 5.0, state: .home), "", "mind"),
            ((accuracy: 20.0, minutesAgo: 5.0, state: .away), "the dentist", "mind"),
            ((accuracy: 20.0, minutesAgo: 5.0, state: .away), "thing:dentist-chair", "mind"),
            // Not a mind: a Wizard's word is no teaching.
            ((accuracy: 20.0, minutesAgo: 5.0, state: .away), "", "person"),
        ] {
            let h = try await harness()
            defer { Task { await h.persistence.cluster.disconnect() } }
            try await h.phone(
                accuracy: setup.accuracy, minutesAgo: setup.minutesAgo, state: setup.state)
            try await h.taught(
                value.isEmpty ? h.dentist.rawValue : value,
                by: source == "mind" ? "mind:beaky" : "wizard:april", kind: source)
            #expect(try await h.pin() == nil)
        }
    }
}
