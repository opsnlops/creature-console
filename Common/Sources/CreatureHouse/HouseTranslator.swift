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
    /// When anything about it last changed, attributes too: a phone's new fix moves this and
    /// leaves `lastChanged` alone while the person stays `home` (#248).
    var lastUpdated: Date? = nil

    var updatedAt: Date { lastUpdated ?? lastChanged }
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
        var events: [WorldEventEnvelope] = []
        if let type = eventType(for: mapping, old: old, new: new) {
            events.append(try event(type, mapping: mapping, old: old, new: new))
        }
        if mapping.kind == .person, let fix = Self.fix(new),
            Self.isNews(fix, at: new.updatedAt, since: old)
        {
            events.append(try located(fix, mapping: mapping, new: new))
        }
        return events
    }

    // MARK: - Where a person is (#248)

    /// A phone's fix, from a person's attributes. Only a GPS source gives `gps_accuracy`: a
    /// network tracker ("connected at home") gives none, and is no fix at all.
    struct Fix: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var accuracy: Double
    }

    static func fix(_ state: EntityState) -> Fix? {
        guard case .number(let latitude)? = state.attributes["latitude"],
            case .number(let longitude)? = state.attributes["longitude"],
            case .number(let accuracy)? = state.attributes["gps_accuracy"]
        else { return nil }
        return Fix(latitude: latitude, longitude: longitude, accuracy: accuracy)
    }

    /// A fix that moved this far from the one the world holds is news.
    static let locationMinimumMove = 25.0
    /// The world holds a fix for half an hour; one this old is told again, so a person sitting
    /// still is not lost.
    static let locationRefresh: TimeInterval = 10 * 60

    /// Whether `fix` is worth telling: the first one, a move of 25 m, one twice as sure, or
    /// the same place once the world's has grown old.
    static func isNews(_ fix: Fix, at time: Date, since old: EntityState?) -> Bool {
        guard let old, let before = Self.fix(old) else { return true }
        return meters(from: before, to: fix) >= locationMinimumMove
            || fix.accuracy <= before.accuracy / 2
            || time.timeIntervalSince(old.updatedAt) >= locationRefresh
    }

    /// The distance between two fixes over the Earth's surface (haversine).
    static func meters(from a: Fix, to b: Fix) -> Double {
        let radius = 6_371_000.0
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let Δφ = φ2 - φ1
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let h = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    private func located(_ fix: Fix, mapping: EntityMapping, new: EntityState) throws
        -> WorldEventEnvelope
    {
        var payload: [String: WorldJSONValue] = [
            "entity_id": .string(new.entityID),
            "latitude": .number(fix.latitude), "longitude": .number(fix.longitude),
            "accuracy_m": .number(fix.accuracy),
        ]
        if case .string(let source)? = new.attributes["source"] {
            payload["source"] = .string(source)
        }
        return try WorldEventEnvelope(
            type: HouseEvents.personLocated,
            occurredAt: new.updatedAt,
            source: EventSource(
                id: try SourceID(validating: "home-assistant:\(Self.sourceName(new.entityID))"),
                kind: HouseEvents.sourceKind,
                // Its own key: the same change may also be an arrival, under the context id.
                sourceEventID: new.contextID.map { "context:\($0):located" }
                    ?? "snapshot:\(WorldJSON.timestamp(new.updatedAt)):located"),
            subjectIDs: [mapping.subjectID],
            epistemic: EpistemicState(
                type: .observed, confidence: 1),
            payload: payload)
    }

    private func event(
        _ type: WorldEventType, mapping: EntityMapping, old: EntityState?, new: EntityState
    ) throws -> WorldEventEnvelope {
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
        return try WorldEventEnvelope(
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
                    || abs(value - previous) < abs(previous) * mapping.minimumChangePercent / 100
            {
                // A small move is still told once the world's value has got old - a fact
                // should never be hours stale because the change was never large.
                let age = new.lastChanged.timeIntervalSince(old.lastChanged)
                guard value != previous, age >= mapping.maximumAgeSeconds else { return nil }
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
