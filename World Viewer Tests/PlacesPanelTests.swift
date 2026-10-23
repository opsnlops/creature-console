import CoreLocation
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

    @Test("Taught places are read from place.geo, longitude first, by name, with who taught them")
    func readsTaughtPlaces() throws {
        let facts = [
            try fact(
                "place:the-hangar", WorldFacts.placeGeo,
                .object([
                    "type": .string("Point"),
                    "coordinates": .array([.number(-100.5), .number(40.5)]),
                    "radius_m": .number(120), "fixes": .number(3),
                    "taught_by": .string("mind:mango"),
                ])),
            try fact(
                "place:dentist", WorldFacts.placeGeo,
                .object([
                    "type": .string("Point"), "coordinates": .array([.number(-100), .number(40)]),
                    "radius_m": .number(75), "fixes": .number(1),
                    "taught_by": .string("mind:beaky"),
                ])),
            // A fix is not a place, and a place with no point is none.
            try fact(
                "person:april", WorldFacts.locationGPS,
                .object(["latitude": .number(40), "longitude": .number(-100)])),
            try fact("place:nowhere", WorldFacts.placeGeo, .string("somewhere")),
        ]
        let places = TaughtPlace.all(in: facts)
        #expect(places.map(\.name) == ["Dentist", "The Hangar"])
        let dentist = try #require(places.first)
        #expect(dentist.latitude == 40 && dentist.longitude == -100)
        #expect(dentist.radius == 75 && dentist.fixes == 1 && dentist.teacher == "Beaky")
        #expect(dentist.since == at)
        #expect(places.last?.teacher == "Mango")
        // Nobody moved either by hand.
        #expect(places.allSatisfy { $0.placer.isEmpty })
    }

    @Test("A place April moved on the map says so (#258)")
    func readsWhoPlacedIt() throws {
        let places = TaughtPlace.all(in: [
            try fact(
                "place:gym", WorldFacts.placeGeo,
                .object([
                    "type": .string("Point"), "coordinates": .array([.number(-100), .number(40)]),
                    "radius_m": .number(75), "fixes": .number(2),
                    "taught_by": .string("mind:beaky"), "placed_by": .string("wizard:april"),
                ]))
        ])
        #expect(places.map(\.placer) == ["April"])
        #expect(places.map(\.teacher) == ["Beaky"])
    }

    @Test(
        "Dragging the pin moves the place as far as the pointer went, not to where it was grabbed")
    func dragMoves() throws {
        let place = try #require(TaughtPlace.all(in: [try dentist(radius: 90)]).first)
        // Grabbed a little off its point, and moved about 230 m north.
        let start = CLLocationCoordinate2D(latitude: 40.0001, longitude: -100.0001)
        let end = CLLocationCoordinate2D(
            latitude: 40.0001 + 230 / 111_195.0, longitude: -100.0001)
        let moved = place.moved(from: start, to: end)
        #expect(abs(moved.latitude - (40 + 230 / 111_195.0)) < 1e-9)
        #expect(abs(moved.longitude - -100) < 1e-9)
        #expect(moved.radius == 90 && moved.id == place.id)
        #expect(
            moved.placement(by: "wizard:april")
                == PlacePlacement(
                    latitude: moved.latitude, longitude: moved.longitude, radius: 90,
                    placedBy: "wizard:april"))
    }

    @Test("Dragging the edge sets how far it reaches, within the world's 75 to 500 m")
    func dragReaches() throws {
        let place = try #require(TaughtPlace.all(in: [try dentist(radius: 90)]).first)
        let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
        // The edge's handle sits as far east as the place reaches.
        let edge = CLLocation(latitude: place.edge.latitude, longitude: place.edge.longitude)
        #expect(abs(center.distance(from: edge) - 90) < 1)
        func north(_ meters: Double) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: 40 + meters / 111_195.0, longitude: -100)
        }
        #expect(abs(place.reaching(north(150)).radius - 150) < 1)
        #expect(place.reaching(north(10)).radius == PlacePlacement.reach.lowerBound)
        #expect(place.reaching(north(3_000)).radius == PlacePlacement.reach.upperBound)
        #expect(place.reaching(north(150)).latitude == place.latitude)
    }

    @Test("Where the world has her: the place, inferred or told, how sure, and since when")
    func readsWhereSheIs() throws {
        var inferred = try fact("person:april", WorldFacts.presencePlace, .string("place:gym"))
        inferred.epistemic = try EpistemicState(type: .inferred, confidence: 0.85)
        let at = try #require(PlacePresence.april(in: [inferred]))
        #expect(
            at
                == PlacePresence(
                    place: try EntityID(validating: "place:gym"), inferred: true,
                    confidence: 0.85, since: self.at))
        #expect(at.name == "Gym")
        var told = try fact("person:april", WorldFacts.presencePlace, .string("place:dentist"))
        told.epistemic = try EpistemicState(type: .reported, confidence: 1)
        #expect(PlacePresence.april(in: [told])?.inferred == false)
        // Words that are no place, and someone else's place, are not where she is.
        #expect(
            PlacePresence.april(in: [
                try fact("person:april", WorldFacts.presencePlace, .string("the dentist"))
            ]) == nil)
        #expect(
            PlacePresence.april(in: [
                try fact("person:jesse", WorldFacts.presencePlace, .string("place:gym"))
            ]) == nil)
    }

    @Test("Inside a circle moves the place, on its rim sets its reach, outside is the map's")
    func grips() {
        let center = CGPoint(x: 200, y: 200)
        // A circle drawn 100 points out.
        #expect(PlaceGrip.at(CGPoint(x: 210, y: 190), center: center, rim: 100) == .move)
        #expect(PlaceGrip.at(CGPoint(x: 295, y: 200), center: center, rim: 100) == .reach)
        #expect(PlaceGrip.at(CGPoint(x: 200, y: 106), center: center, rim: 100) == .reach)
        #expect(PlaceGrip.at(CGPoint(x: 320, y: 200), center: center, rim: 100) == nil)
        // Zoomed out, a circle a few points across only moves, caught just past its edge.
        #expect(PlaceGrip.at(CGPoint(x: 206, y: 200), center: center, rim: 3) == .move)
        #expect(PlaceGrip.at(CGPoint(x: 220, y: 200), center: center, rim: 3) == nil)
    }

    @Test("A place's name hangs on its circle's southern rim")
    func nameHangsSouth() throws {
        let place = try #require(TaughtPlace.all(in: [try dentist(radius: 90)]).first)
        let south = CLLocation(latitude: place.south.latitude, longitude: place.south.longitude)
        let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
        #expect(abs(center.distance(from: south) - 90) < 1)
        #expect(place.south.latitude < place.latitude && place.south.longitude == place.longitude)
    }

    private func dentist(radius: Double) throws -> Fact {
        try fact(
            "place:dentist", WorldFacts.placeGeo,
            .object([
                "type": .string("Point"), "coordinates": .array([.number(-100), .number(40)]),
                "radius_m": .number(radius), "fixes": .number(1),
                "taught_by": .string("mind:beaky"),
            ]))
    }
}
