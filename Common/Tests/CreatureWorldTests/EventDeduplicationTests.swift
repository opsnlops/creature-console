import Foundation
import Logging
import MongoCore
import MongoKitten
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = TestDatabase.isolated("deduplication")

/// How often each index of a collection has answered a query, from `$indexStats`.
private struct IndexStats: AggregateBuilderStage {
    let stage: Document = ["$indexStats": [:] as Document]
    let minimalVersionRequired: WireVersion? = nil
}

/// Every event is checked against the log by its source before it is accepted. The check scanned
/// the whole log, because the planner cannot use a partial index whose condition the query does
/// not state (#299).
@Suite(
    "The duplicate check, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct EventDeduplicationMongoTests {
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    private func motion(_ sourceEventID: String) throws -> WorldEventEnvelope {
        let hall = try EntityID(validating: "place:hall")
        return try WorldEventEnvelope(
            type: HouseEvents.motionDetected, occurredAt: now,
            source: EventSource(
                id: try SourceID(validating: "home-assistant:dedup-tests"),
                kind: HouseEvents.sourceKind, sourceEventID: sourceEventID),
            subjectIDs: [hall], placeID: hall,
            epistemic: EpistemicState(type: .observed, confidence: 1), payload: [:])
    }

    private func uses(of index: String, in database: MongoDatabase) async throws -> Int {
        let rows = try await database[MongoWorldCollection.events]
            .buildAggregate { IndexStats() }.drain()
        let row = try #require(rows.first { $0["name"] as? String == index })
        let accesses = try #require(row["accesses"] as? Document)
        return try #require((accesses["ops"] as? Int) ?? (accesses["ops"] as? Int32).map(Int.init))
    }

    @Test("A new event and a repeated one are both looked up in the source index")
    func duplicateCheckUsesItsIndex() async throws {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "deduplication-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let before = try await uses(of: "source_event_unique", in: persistence.database)

        let sourceEventID = UUID().uuidString
        let first = try motion(sourceEventID)
        guard
            case .inserted(let accepted) = try await persistence.events.append(
                first, receivedAt: now)
        else {
            Issue.record("the first event was not inserted")
            return
        }
        // The same happening told again, under a new event id.
        let again = try await persistence.events.append(motion(sourceEventID), receivedAt: now)
        #expect(again == .duplicateSourceEvent(accepted))

        let after = try await uses(of: "source_event_unique", in: persistence.database)
        #expect(after - before >= 2)
    }
}
