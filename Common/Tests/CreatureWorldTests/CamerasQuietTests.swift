import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = TestDatabase.uri

/// A sighting is judged by when it was seen (#266): the scene opener reads the world one event
/// at a time, and a sighting seen in the cameras' quiet and read just after it ended opened a
/// scene April had asked to skip.
@Suite(
    "The cameras' quiet at a moment, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct CamerasQuietMongoTests {
    // Now, in whole seconds: events expire by kind, and an old one can be swept mid-test.
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    @Test(
        "Quiet while the quiet was in force, and not before it, after it ended, or once it ran out")
    func quietAtAMoment() async throws {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "cameras-quiet-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [GivenFactReducer()], clock: ManualWorldClock(now: now))
        let house = try EntityID(validating: "house:quiet-\(UUID().uuidString.lowercased())")
        func given(_ value: WorldJSONValue, at moment: Date, for seconds: Double) async throws {
            _ = try await world.accept(
                try WorldEventEnvelope(
                    type: GivenFactAnnouncement.eventType, occurredAt: moment,
                    source: EventSource(
                        id: SourceID(validating: "mind:beaky"), kind: "mind",
                        sourceEventID: UUID().uuidString),
                    subjectIDs: [house],
                    epistemic: EpistemicState(type: .reported, confidence: 1),
                    payload: [
                        "subject_id": .string(house.rawValue),
                        "predicate": .string(WorldFacts.camerasQuiet), "value": value,
                        "valid_for_seconds": .number(seconds),
                    ]))
        }
        func quiet(_ offset: TimeInterval) async throws -> Bool {
            try await Household.camerasQuiet(
                house: house, facts: persistence.facts, at: now.addingTimeInterval(offset))
        }
        // "The yard guy is working" for an hour from -10 s, and a bird ends it early at 0.
        try await given(.string("the yard guy is working"), at: now - 10, for: 3_600)
        try await given(.null, at: now, for: 1)

        #expect(try await quiet(-11) == false)
        // Seen in the quiet, and only read once it ended: still the quiet's.
        #expect(try await quiet(-5))
        #expect(try await quiet(-0.5))
        #expect(try await quiet(0.5) == false)
        #expect(try await quiet(5) == false)

        // A quiet that simply runs out.
        let shed = try EntityID(validating: "house:quiet-\(UUID().uuidString.lowercased())")
        _ = try await world.accept(
            try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType, occurredAt: now - 60,
                source: EventSource(
                    id: SourceID(validating: "mind:beaky"), kind: "mind",
                    sourceEventID: UUID().uuidString),
                subjectIDs: [shed], epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: [
                    "subject_id": .string(shed.rawValue),
                    "predicate": .string(WorldFacts.camerasQuiet), "value": .string("a nap"),
                    "valid_for_seconds": .number(30),
                ]))
        #expect(
            try await Household.camerasQuiet(
                house: shed, facts: persistence.facts, at: now.addingTimeInterval(-45)))
        #expect(
            try await Household.camerasQuiet(
                house: shed, facts: persistence.facts, at: now.addingTimeInterval(-29)) == false)
    }
}
