import Foundation
import WorldCore

/// Who is about, as the house knows it, the moment a camera sees someone: April's presence
/// from the sensor, and whoever is expected. April lives alone; the stage note carries this so
/// the minds never guess at a shape. Read afresh for every occasion - a scene's note is about
/// now.
enum Household {
    static let april = try! EntityID(validating: "person:april")

    static func situation(facts: FactRepository, at now: Date) async throws -> HouseholdSituation {
        situation(
            aprilFacts: try await facts.currentFacts(subjectID: april, at: now),
            expected: try await facts.currentFacts(
                subjectID: nil, predicatePrefix: WorldFacts.visitorExpected, after: nil, limit: 5,
                at: now))
    }

    /// `presence.state` on April, and every `visitor.expected` in force - on the house, or on
    /// the person coming (the calendar's rule casts it there).
    static func situation(aprilFacts: [Fact], expected: [Fact]) -> HouseholdSituation {
        let home: Bool?
        if case .string(let state)? = aprilFacts.first(where: {
            $0.predicate == WorldFacts.personState
        })?.value {
            home = state == PersonPresenceState.home.rawValue
        } else {
            home = nil
        }
        let visitors = expected.compactMap { fact -> String? in
            guard case .string(let words) = fact.value, !words.isEmpty else { return nil }
            if fact.subjectID.rawValue.hasPrefix("person:") {
                return "\(SceneOpeningPolicy.placeName(fact.subjectID)), \(words)"
            }
            return words
        }
        return HouseholdSituation(
            aprilHome: home,
            visitorExpected: visitors.isEmpty ? nil : visitors.joined(separator: "; "))
    }

    static let sourceID = try! SourceID(validating: "world:household")
    /// How long the house's word on a sighting stands: long enough to cover the visit to the
    /// kitchen, short enough that a real visitor an hour later is not called April.
    static let identificationLifetime: TimeInterval = 30 * 60

    /// The house's own word on who a camera saw, as a fact: `sighting.identified = April` on
    /// the place, when she is home and nobody is expected. The stage note says it to the
    /// birds in the moment (#200); this writes it into the record, so the day's story, the
    /// Viewer, and a question an hour later agree with what was said. Nil when the house
    /// cannot say.
    static func identification(
        of event: WorldEventEnvelope, place: EntityID, situation: HouseholdSituation, now: Date
    ) throws -> WorldEventEnvelope? {
        guard event.type == HouseEvents.personSeen, situation.aprilHome == true,
            situation.visitorExpected == nil
        else { return nil }
        return try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType,
            occurredAt: now,
            source: EventSource(
                id: sourceID, kind: "world", sourceEventID: "identified:\(event.eventID.rawValue)"),
            subjectIDs: [place, april],
            placeID: place,
            epistemic: EpistemicState(type: .assumed, confidence: 0.95),
            payload: [
                "subject_id": .string(place.rawValue),
                "predicate": .string(WorldFacts.sightingIdentified),
                "value": .string("April"),
                "valid_for_seconds": .number(identificationLifetime),
            ],
            causedBy: [.event(event.eventID)])
    }
}
