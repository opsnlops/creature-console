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
        if let old, type == HouseEvents.personGone || type == HouseEvents.vehicleGone {
            payload["after_seconds"] = .number(
                new.lastChanged.timeIntervalSince(old.lastChanged).rounded())
        }
        if mapping.kind == .media, let predicate = mapping.predicate {
            payload["predicate"] = .string(predicate)
            payload["value"] = Self.mediaWords(new).map { .string($0) } ?? .null
        }
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
        // A media player's words are what matter: a new title under the same `playing` state
        // is news, a device going unavailable is the TV going off, and nothing else is.
        if mapping.kind == .media {
            let now = Self.mediaWords(new)
            if let old {
                return Self.mediaWords(old) == now ? nil : HouseEvents.mediaChanged
            }
            // At startup, always: an "on" the world kept from before a restart is ended.
            return HouseEvents.mediaChanged
        }
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
        case .media:
            return nil  // decided above
        case .detection:
            // A detection is a moment; only the moment it happens is news, and at startup a
            // camera that happens to be seeing something is not "news" either. Its end is news
            // too, once it has lasted: a car that sat in the driveway for two hours has gone -
            // the cleaners leaving - while a car that passed is nothing twice.
            guard let old else { return nil }
            if old.state == "on", new.state == "off" {
                guard new.lastChanged.timeIntervalSince(old.lastChanged) >= mapping.goneAfterSeconds
                else { return nil }
                switch mapping.detects {
                case .person?: return HouseEvents.personGone
                case .vehicle?: return HouseEvents.vehicleGone
                default: return nil  // animals never wake the birds, coming or going
                }
            }
            guard new.state == "on" else { return nil }
            switch mapping.detects {
            case .person?: return HouseEvents.personSeen
            case .vehicle?: return HouseEvents.vehicleSeen
            case .animal?: return HouseEvents.animalSeen
            case nil: return nil
            }
        }
    }

    /// What a media player is doing, in words the birds can say - or nil when it is off,
    /// asleep, idle with nothing on it, or gone:
    /// - a TV that is only on: "on"
    /// - a receiver: "Apple TV, volume 40%"
    /// - a player with something on it: "YouTube: <title>", "by <artist>", "(paused)".
    /// Volume in tens, so a nudge of the knob is not news.
    static func mediaWords(_ state: EntityState) -> String? {
        let active: Set<String> = ["on", "playing", "paused", "buffering"]
        guard active.contains(state.state) else { return nil }
        func text(_ key: String) -> String? {
            if case .string(let value)? = state.attributes[key], !value.isEmpty { return value }
            return nil
        }
        var what: String
        let app = text("app_name")
        if let title = text("media_title"), title != text("source") {
            what = app.map { "\($0): \(title)" } ?? title
            if let series = text("media_series_title") {
                what += " (\(series))"
            } else if let artist = text("media_artist") {
                what += " by \(artist)"
            }
        } else if let app {
            what = app
        } else if let source = text("source") {
            what = source
            if case .number(let volume)? = state.attributes["volume_level"] {
                what += ", volume \(Int((volume * 10).rounded()) * 10)%"
            }
        } else {
            what = "on"
        }
        if state.state == "paused" { what += " (paused)" }
        return what
    }

    /// `lock.front_door` → `lock-front-door`: a source id is `kind:name`, one colon.
    static func sourceName(_ entityID: String) -> String {
        entityID.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "_", with: "-")
    }
}
