import Foundation
import WorldCore

/// Where April is, without being told (#248, slice 3): on each fix from her phone, the nearest
/// taught place whose circle reaches her - MongoDB's `$geoNear` over the pins - becomes
/// `presence.place` on her, inferred. A fix outside the place she is at ends it. A still phone
/// sends nothing (seen 2026-10-22: 39 minutes at the dentist, 70 at the gym), so a place lasts
/// until a fix elsewhere or until she is home, never by its age. The birds are told the place,
/// never the point.
actor PlaceInferenceRule {
    /// How sure the world is with her at a place's pin, and at the edge of its reach.
    static let sureAtPin = 0.95
    static let sureAtEdge = 0.7

    private let facts: FactRepository
    private let accept: @Sendable (WorldEventEnvelope) async throws -> Void

    init(
        facts: FactRepository, accept: @escaping @Sendable (WorldEventEnvelope) async throws -> Void
    ) {
        self.facts = facts
        self.accept = accept
    }

    /// How sure the world is that she is at a place `meters` from its pin, the place and her fix
    /// together reaching `reach`.
    static func confidence(meters: Double, reach: Double) -> Double {
        let way = reach > 0 ? min(max(meters / reach, 0), 1) : 0
        return sureAtPin - (sureAtPin - sureAtEdge) * way
    }

    /// An event from the world's stream; anything but a fix from the house is ignored.
    func heard(_ event: WorldEventEnvelope) async throws {
        guard event.type == HouseEvents.personLocated, let person = event.subjectIDs.first,
            case .number(let latitude)? = event.payload["latitude"],
            case .number(let longitude)? = event.payload["longitude"],
            case .number(let accuracy)? = event.payload["accuracy_m"],
            accuracy <= PlaceTeachingRule.vaguest
        else { return }
        let now = event.occurredAt
        let current = try await facts.currentFacts(subjectID: person, at: now)
        // At the house the house knows, and arriving there ends every place.
        let home = WorldJSONValue.string(PersonPresenceState.home.rawValue)
        if current.contains(where: { $0.predicate == WorldFacts.personState && $0.value == home }) {
            return
        }
        let here = current.first { $0.predicate == WorldFacts.presencePlace }
        let at = here.flatMap { WorldFacts.link(in: $0.value) }

        let near = try await facts.placesNear(
            latitude: latitude, longitude: longitude, slack: accuracy, at: now)
        if let (pin, meters) = near.first {
            // Already there, by her word or the world's: when she arrived stays as it was.
            guard pin.subjectID != at else { return }
            let reach = (PlacePin(pin.value)?.radius ?? 0) + accuracy
            try await cast(
                .string(pin.subjectID.rawValue), on: person, from: event,
                epistemic: EpistemicState(
                    type: .inferred, confidence: Self.confidence(meters: meters, reach: reach)),
                causedBy: [.event(event.eventID), .fact(pin.factID)], key: "at")
            return
        }
        // Out of every place's reach. If she is at a place with a pin, she has left it; one told
        // without a fix to pin it cannot be judged by a point, and keeps its own end.
        guard let here, let at,
            let pin = try await facts.currentFacts(subjectID: at, at: now)
                .first(where: { $0.predicate == WorldFacts.placeGeo })
        else { return }
        try await cast(
            .null, on: person, from: event,
            epistemic: EpistemicState(type: .inferred, confidence: 1),
            causedBy: [.event(event.eventID), .fact(here.factID), .fact(pin.factID)], key: "left",
            validFor: 1)
    }

    private func cast(
        _ value: WorldJSONValue, on person: EntityID, from fix: WorldEventEnvelope,
        epistemic: EpistemicState, causedBy: [ProvenanceReference], key: String,
        validFor seconds: Double? = nil
    ) async throws {
        var payload: [String: WorldJSONValue] = [
            "subject_id": .string(person.rawValue),
            "predicate": .string(WorldFacts.presencePlace),
            "value": value,
        ]
        if let seconds { payload["valid_for_seconds"] = .number(seconds) }
        try await accept(
            try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType,
                occurredAt: fix.occurredAt,
                source: EventSource(
                    id: PlaceTeachingRule.sourceID, kind: "world",
                    // One answer per fix: a replayed event changes nothing.
                    sourceEventID: "\(key):\(fix.eventID.rawValue)"),
                subjectIDs: [person],
                epistemic: epistemic,
                payload: payload,
                causedBy: causedBy,
                trace: fix.trace))
    }
}
