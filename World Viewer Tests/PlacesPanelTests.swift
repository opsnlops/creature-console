import Foundation
import Testing
import WorldCore

@testable import World_Viewer

/// April's phone's fix on the Places panel (#248). A made-up point in the middle of Kansas:
/// never April's (the repository is public).
@Suite("Where April is, on the map")
struct PlaceFixTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func fact(_ subject: String, _ predicate: String, _ value: WorldJSONValue) throws
        -> Fact
    {
        try Fact(
            subjectID: EntityID(validating: subject), predicate: predicate, value: value,
            epistemic: EpistemicState(type: .observed, confidence: 1), validFrom: at,
            derivedFrom: [], producer: FactProducer(kind: "presence", id: "house", version: "1"))
    }

    @Test("The fix is read from April's location.gps, with how sure and since when")
    func readsTheFix() throws {
        let facts = [
            try fact("person:april", WorldFacts.personState, .string("home")),
            try fact(
                "person:april", WorldFacts.locationGPS,
                .object([
                    "latitude": .number(40.0), "longitude": .number(-100.0),
                    "accuracy_m": .number(12),
                ])),
            // Someone else's phone is not April's.
            try fact(
                "person:jesse", WorldFacts.locationGPS,
                .object(["latitude": .number(1), "longitude": .number(1)])),
        ]
        let fix = try #require(PlaceFix.april(in: facts))
        #expect(fix == PlaceFix(latitude: 40, longitude: -100, accuracy: 12, since: at))
        #expect(fix.coordinate.latitude == 40)
        #expect(PlaceFix.april(in: Array(facts.prefix(1))) == nil)
    }
}
