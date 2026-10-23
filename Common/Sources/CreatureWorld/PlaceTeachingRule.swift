import Foundation
import WorldCore

/// A phone's fix, as the world keeps it in `location.gps` (#248).
struct PhoneFix: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// How sure, in meters. The house sends a fix only with one.
    var accuracy: Double
    var at: Date

    init(latitude: Double, longitude: Double, accuracy: Double, at: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.at = at
    }

    /// The fix a `location.gps` fact holds; nil for anything else, or a fix that does not say
    /// how sure it is.
    init?(_ fact: Fact) {
        guard fact.predicate == WorldFacts.locationGPS, case .object(let fields) = fact.value,
            case .number(let latitude)? = fields["latitude"],
            case .number(let longitude)? = fields["longitude"],
            case .number(let accuracy)? = fields["accuracy_m"]
        else { return nil }
        self.init(latitude: latitude, longitude: longitude, accuracy: accuracy, at: fact.validFrom)
    }
}

/// Where a place April taught is (#248): a point, how far it reaches, and how many times her
/// phone was there when she said so. The arithmetic, apart from the store.
struct PlacePin: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// How far the place reaches from its point, in meters.
    var radius: Double
    var fixes: Int
    /// The mind that kept her word last: `mind:beaky`.
    var taughtBy: String
    /// The Wizard who put it where it is by hand, on the Viewer's map (#258); nil while it is
    /// where her phone was.
    var placedBy: String?

    /// The least a taught place reaches and the most, the same for April's hand on the map.
    static let minimumRadius = PlacePlacement.reach.lowerBound
    static let maximumRadius = PlacePlacement.reach.upperBound
    /// Taught farther than this from its pin, a place has moved, or was taught by mistake: the
    /// newest word wins, and it is pinned afresh.
    static let movedDistance: Double = 1_000

    init(
        latitude: Double, longitude: Double, radius: Double, fixes: Int, taughtBy: String,
        placedBy: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.fixes = fixes
        self.taughtBy = taughtBy
        self.placedBy = placedBy
    }

    /// The pin a `place.geo` value holds; nil for anything else.
    init?(_ value: WorldJSONValue) {
        guard case .object(let fields) = value,
            case .array(let coordinates)? = fields["coordinates"], coordinates.count == 2,
            case .number(let longitude) = coordinates[0],
            case .number(let latitude) = coordinates[1],
            case .number(let radius)? = fields["radius_m"],
            case .number(let fixes)? = fields["fixes"]
        else { return nil }
        var taughtBy = ""
        if case .string(let teacher)? = fields["taught_by"] { taughtBy = teacher }
        var placedBy: String?
        if case .string(let wizard)? = fields["placed_by"] { placedBy = wizard }
        self.init(
            latitude: latitude, longitude: longitude, radius: radius, fixes: max(Int(fixes), 1),
            taughtBy: taughtBy, placedBy: placedBy)
    }

    /// As `place.geo` holds it: a GeoJSON point, longitude first, so it can be indexed as it is.
    var value: WorldJSONValue {
        var fields: [String: WorldJSONValue] = [
            "type": .string("Point"),
            "coordinates": .array([.number(longitude), .number(latitude)]),
            "radius_m": .number(radius.rounded()),
            "fixes": .number(Double(fixes)),
            "taught_by": .string(taughtBy),
        ]
        if let placedBy { fields["placed_by"] = .string(placedBy) }
        return .object(fields)
    }

    /// The pin after April says she is there, her phone at `fix`: the running mean of the
    /// fixes, its reach grown to cover where the old circle was and where she is now. A pin she
    /// placed by hand stays where she put it, and only counts the fix: "Keep mine" (#258).
    static func taught(_ pin: PlacePin?, at fix: PhoneFix, by teacher: String) -> PlacePin {
        let least = min(max(minimumRadius, fix.accuracy), maximumRadius)
        guard let pin,
            distance(pin.latitude, pin.longitude, fix.latitude, fix.longitude) <= movedDistance
        else {
            return PlacePin(
                latitude: fix.latitude, longitude: fix.longitude, radius: least, fixes: 1,
                taughtBy: teacher)
        }
        if pin.placedBy != nil {
            var kept = pin
            kept.fixes += 1
            kept.taughtBy = teacher
            return kept
        }
        let weight = Double(pin.fixes)
        let latitude = (pin.latitude * weight + fix.latitude) / (weight + 1)
        let longitude = (pin.longitude * weight + fix.longitude) / (weight + 1)
        let shift = distance(pin.latitude, pin.longitude, latitude, longitude)
        let reach = distance(latitude, longitude, fix.latitude, fix.longitude)
        return PlacePin(
            latitude: latitude, longitude: longitude,
            radius: min(max(least, pin.radius + shift, reach), maximumRadius),
            fixes: pin.fixes + 1, taughtBy: teacher)
    }

    /// The pin after April moves it on the map (#258): where she put it, as far as she drew it
    /// within a taught place's bounds. Its fixes and its teacher stay.
    static func placed(_ pin: PlacePin, as placement: PlacePlacement) -> PlacePin {
        PlacePin(
            latitude: placement.latitude, longitude: placement.longitude,
            radius: min(max(placement.radius, minimumRadius), maximumRadius), fixes: pin.fixes,
            taughtBy: pin.taughtBy, placedBy: placement.placedBy)
    }

    /// Meters between two points on the Earth (haversine).
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double)
        -> Double
    {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians
        let dLon = (lon2 - lon1) * radians
        let a =
            sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// April teaches the birds her places (#248, slice 2): a bird keeping her word "I'm at the
/// dentist" as `person:april presence.place = place:dentist` pins `place:dentist` where her
/// phone is right now. The bird judges what she meant; this only reads the link it kept and
/// the fix the house sent. The pin is the world's alone - a bird is told a place, never a point.
/// April may move a pin on the Viewer's map, and it stays where she puts it (#258).
actor PlaceTeachingRule {
    static let sourceID = try! SourceID(validating: "world:places")
    /// The oldest fix that still says where she is: the house sends a still phone's every ten
    /// minutes.
    static let freshness: TimeInterval = 15 * 60
    /// The vaguest fix a place is pinned from, in meters.
    static let vaguest: Double = 100

    private let facts: FactRepository
    private let accept: @Sendable (WorldEventEnvelope) async throws -> Void

    init(
        facts: FactRepository, accept: @escaping @Sendable (WorldEventEnvelope) async throws -> Void
    ) {
        self.facts = facts
        self.accept = accept
    }

    /// An event from the world's stream; anything but a mind keeping where someone is, at a
    /// place, is ignored.
    func heard(_ event: WorldEventEnvelope) async throws {
        guard event.type == GivenFactAnnouncement.eventType, event.source.kind == "mind",
            case .string(WorldFacts.presencePlace)? = event.payload["predicate"],
            let value = event.payload["value"], let place = WorldFacts.link(in: value),
            place.rawValue.hasPrefix("place:"),
            case .string(let raw)? = event.payload["subject_id"],
            let person = EntityID(rawValue: raw)
        else { return }
        let now = event.occurredAt
        let current = try await facts.currentFacts(subjectID: person, at: now)
        // At the house the house knows, and a room taught there ("I'm in the workshop") would
        // claim the house's own point.
        let home = WorldJSONValue.string(PersonPresenceState.home.rawValue)
        if current.contains(where: { $0.predicate == WorldFacts.personState && $0.value == home }) {
            return
        }
        guard let gps = current.first(where: { $0.predicate == WorldFacts.locationGPS }),
            let fix = PhoneFix(gps), now.timeIntervalSince(fix.at) <= Self.freshness,
            fix.accuracy <= Self.vaguest
        else { return }
        let pinned = try await facts.currentFacts(subjectID: place, at: now)
            .first { $0.predicate == WorldFacts.placeGeo }
            .flatMap { PlacePin($0.value) }
        let pin = PlacePin.taught(pinned, at: fix, by: event.source.id.rawValue)
        try await accept(
            try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType,
                occurredAt: now,
                source: EventSource(
                    id: Self.sourceID, kind: "world",
                    // One pin per teaching: a replayed event changes nothing.
                    sourceEventID: "place:\(event.eventID.rawValue)"),
                subjectIDs: [place],
                epistemic: EpistemicState(type: .inferred, confidence: 1),
                payload: [
                    "subject_id": .string(place.rawValue),
                    "predicate": .string(WorldFacts.placeGeo),
                    "value": pin.value,
                ],
                causedBy: [.event(event.eventID), .fact(gps.factID)],
                trace: event.trace))
    }

    /// April moving a place on the Viewer's map (#258): the cast that puts its pin where she
    /// dropped it, in her word. Nil for a place the world never pinned.
    func placement(of place: EntityID, _ placement: PlacePlacement, at now: Date) async throws
        -> WorldEventEnvelope?
    {
        guard
            let current = try await facts.currentFacts(subjectID: place, at: now)
                .first(where: { $0.predicate == WorldFacts.placeGeo }),
            let pin = PlacePin(current.value)
        else { return nil }
        return try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType,
            occurredAt: now,
            source: EventSource(
                id: try SourceID(validating: placement.placedBy), kind: "person",
                sourceEventID: UUID().uuidString),
            subjectIDs: [place],
            epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: [
                "subject_id": .string(place.rawValue),
                "predicate": .string(WorldFacts.placeGeo),
                "value": PlacePin.placed(pin, as: placement).value,
            ],
            causedBy: [.fact(current.factID)])
    }
}
