import Foundation
import WorldCore

/// A Home Assistant state, as the adapter sees it.
struct EntityState: Equatable, Sendable {
    var entityID: String
    var state: String
    var attributes: [String: WorldJSONValue]
    var lastChanged: Date
    /// Home Assistant's context id for the change; the world's idempotency key.
    var contextID: String?
}

/// Pure: a state change in, world events out. The source vocabulary (`on`, `not_home`, entity
/// ids) stops here; the world hears about doors, motion, people, and measurements.
struct HouseTranslator: Sendable {
    let mappings: [String: EntityMapping]

    init(mappings: [EntityMapping]) {
        self.mappings = Dictionary(uniqueKeysWithValues: mappings.map { ($0.entityID, $0) })
    }

    /// Events for a change from `old` to `new`; `old` is `nil` at startup (the snapshot),
    /// when every mapped entity's current state is announced once.
    func events(from old: EntityState?, to new: EntityState) throws -> [WorldEventEnvelope] {
        guard let mapping = mappings[new.entityID] else { return [] }
        guard let type = eventType(for: mapping, old: old, new: new) else { return [] }
        var payload: [String: WorldJSONValue] = [
            "entity_id": .string(new.entityID),
            "state": .string(new.state),
        ]
        if let old { payload["previous_state"] = .string(old.state) }
        if mapping.kind == .measurement, let predicate = mapping.predicate,
            let value = Double(new.state)
        {
            payload["predicate"] = .string(predicate)
            payload["value"] = .number(value)
            if case .string(let unit)? = new.attributes["unit_of_measurement"] {
                payload["unit"] = .string(unit)
            }
        }
        let isPlace = mapping.subjectID.rawValue.hasPrefix("place:")
        return [
            try WorldEventEnvelope(
                type: type,
                occurredAt: new.lastChanged,
                source: EventSource(
                    id: try SourceID(validating: "home-assistant:\(Self.sourceName(new.entityID))"),
                    kind: HouseEvents.sourceKind,
                    // The same change delivered twice (a reconnect, a replayed outbox) is the
                    // same event; a snapshot is keyed by when the state last changed.
                    sourceEventID: new.contextID.map { "context:\($0)" }
                        ?? "snapshot:\(WorldJSON.timestamp(new.lastChanged)):\(new.state)"),
                subjectIDs: [mapping.subjectID],
                placeID: isPlace ? mapping.subjectID : nil,
                epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: payload
            )
        ]
    }

    private func eventType(for mapping: EntityMapping, old: EntityState?, new: EntityState)
        -> WorldEventType?
    {
        // Home Assistant says `unknown` / `unavailable` when a device is gone; that is not news.
        let dead: Set<String> = ["unknown", "unavailable", ""]
        guard !dead.contains(new.state) else { return nil }
        if let old, old.state == new.state, mapping.kind != .measurement { return nil }
        switch mapping.kind {
        case .lock:
            switch new.state {
            case "locked": return HouseEvents.doorLocked
            case "unlocked": return HouseEvents.doorUnlocked
            default: return nil
            }
        case .door:
            return new.state == "on" ? HouseEvents.doorOpened : HouseEvents.doorClosed
        case .motion:
            return new.state == "on" ? HouseEvents.motionDetected : HouseEvents.motionCleared
        case .person:
            let home = new.state == "home"
            if let old, (old.state == "home") == home { return nil }
            return home ? HouseEvents.personArrived : HouseEvents.personLeft
        case .measurement:
            guard let value = Double(new.state) else { return nil }
            if let old, let previous = Double(old.state),
                abs(value - previous) < mapping.minimumChange
            {
                return nil
            }
            return HouseEvents.measurementChanged
        case .detection:
            // A detection is a moment; only the moment it happens is news, and at startup a
            // camera that happens to be seeing something is not "news" either.
            guard new.state == "on", old != nil else { return nil }
            switch mapping.detects {
            case .person?: return HouseEvents.personSeen
            case .vehicle?: return HouseEvents.vehicleSeen
            case .animal?: return HouseEvents.animalSeen
            case nil: return nil
            }
        }
    }

    /// `lock.front_door` → `lock-front-door`: a source id is `kind:name`, one colon.
    static func sourceName(_ entityID: String) -> String {
        entityID.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "_", with: "-")
    }
}
