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
        if mapping.kind == .game {
            return try gameEvent(mapping: mapping, old: old, new: new).map { [$0] } ?? []
        }
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

    /// What to remember of a state the World was just told about. For a game, the side last
    /// known to have the ball outlives an update that names nobody: ESPN says nothing of
    /// possession on a scoring play, and remembering that blank made the kickoff that followed
    /// - the scorers still on the ball - read as the ball changing hands ("Seattle Seahawks now
    /// has the ball" after their own field goal, #272).
    func remembered(_ new: EntityState, after old: EntityState?) -> EntityState {
        guard mappings[new.entityID]?.kind == .game, let old,
            TeamTrackerGame.side(in: new) == nil, TeamTrackerGame.side(in: old) != nil
        else { return new }
        var kept = new
        kept.attributes["possession"] = old.attributes["possession"]
        return kept
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

    // MARK: - A team's game (#269)

    /// What a Team Tracker sensor's change is: a game at a stage the World has not heard; while
    /// it is under way a score, the ball changing hands, a review's ruling, a flag or a first
    /// down (#287); or nothing. Odds, the clock, the
    /// downs and records moving under the same state are not news, and nor is a sensor gone and
    /// back - `old` is what the World was last told.
    private func gameEvent(mapping: EntityMapping, old: EntityState?, new: EntityState) throws
        -> WorldEventEnvelope?
    {
        guard let game = TeamTrackerGame(new) else { return nil }
        let before = old.flatMap { TeamTrackerGame($0) }
        let sameGame = before?.kickoff == game.kickoff
        let type: WorldEventType
        let key: String
        var scored: TeamTrackerGame.Scored?
        // When it happened: a new stage is a new state, so `last_changed`. A score changes only
        // the attributes, which move `last_updated` alone; by `last_changed` every score of the
        // Bears game happened at kickoff (#271).
        var happened = new.lastChanged
        if sameGame, let before, before.stage == game.stage {
            // Under way, a score is news: April wants the birds asked about each one. A
            // correction that only takes points away is news of its own. Keyed by the change
            // itself, not the score: a touchdown overturned on review and scored again is two
            // scores of the same number.
            guard game.stage == .playing else { return nil }
            let scoreMoved =
                game.teamScore != before.teamScore || game.opponentScore != before.opponentScore
            // The ball changing hands, which April wants the birds asked about too. ESPN saying
            // nothing between plays is not a change; the side known again after it is, if it
            // is the other one. A score is the bigger news when both move in one look.
            let ballMoved = game.possession != nil && game.possession != before.possession
            // A play the World has not heard (#287): ESPN's write-up of it differs from the
            // last one told. The down and the write-up can arrive in separate looks, so both
            // are compared with what the World last heard, not with the look before.
            let newPlay = game.lastPlay != nil && game.lastPlay != before.lastPlay
            // One play is one piece of news, the biggest: a score, the ball changing hands, a
            // review's ruling, a flag, a first down, then any other play - a flag's automatic
            // first down is the flag.
            let kind: String
            if scoreMoved {
                scored = game.scored(since: before)
                type = scored == nil ? HouseEvents.gameScoreCorrected : HouseEvents.gameScored
                kind = "score"
            } else if ballMoved {
                type = HouseEvents.gamePossession
                kind = "possession"
            } else if newPlay, game.review != nil {
                type = HouseEvents.gameReviewed
                kind = "review"
            } else if newPlay, game.penalty != nil {
                type = HouseEvents.gamePenalty
                kind = "penalty"
            } else if newPlay, game.possession != nil, game.isFirstDown,
                game.downDistance != before.downDistance
            {
                type = HouseEvents.gameFirstDown
                kind = "first-down"
            } else if newPlay, game.downDistance != nil, game.downDistance != before.downDistance {
                // Any other snap (#287): April wanted the birds to say more. The down moving
                // is what makes it a play - a timeout's write-up moves nothing.
                type = HouseEvents.gamePlay
                kind = "play"
            } else {
                return nil
            }
            happened = new.updatedAt
            key =
                new.contextID.map { "context:\($0)" }
                ?? "game:\(WorldJSON.timestamp(game.kickoff)):\(kind):\(WorldJSON.timestamp(happened))"
        } else {
            let stage: String
            (type, stage) =
                switch game.stage {
                case .scheduled: (HouseEvents.gameScheduled, "scheduled")
                case .playing: (HouseEvents.gameStarted, "started")
                case .final: (HouseEvents.gameFinal, "final")
                }
            // One event per game and stage, whoever tells it first: a restart's snapshot of a
            // final the World heard live is the same event, and changes nothing.
            key = "game:\(WorldJSON.timestamp(game.kickoff)):\(stage)"
        }
        var payload: [String: WorldJSONValue] = [
            "entity_id": .string(new.entityID), "state": .string(new.state),
            "kickoff": .string(WorldJSON.timestamp(game.kickoff)),
        ]
        payload["team"] = game.team.map { .string($0) }
        payload["opponent"] = game.opponent.map { .string($0) }
        payload["home_away"] = game.homeAway.map { .string($0) }
        payload["result"] = game.result.map { .string($0) }
        payload["clock"] = game.clock.map { .string($0) }
        // A write-up the World already heard is the last play's, not this one's: ESPN moves
        // the score before it writes the play up, and the field goal on 11-08 reached the
        // birds as the run before it again, so Beaky passed - "already celebrated this play".
        let stalePlay = sameGame && before?.stage == .playing && game.lastPlay == before?.lastPlay
        payload["last_play"] = stalePlay ? nil : game.lastPlay.map { .string($0) }
        payload["possession"] = game.possession.map { .string($0) }
        payload["down_distance"] = game.downDistance.map { .string($0) }
        if type == HouseEvents.gamePenalty, let penalty = game.penalty {
            payload["penalty_on"] = .string(penalty.on)
            payload["foul"] = .string(penalty.foul)
            payload["yards"] = penalty.yards.map { .number(Double($0)) }
        }
        if type == HouseEvents.gameReviewed, let review = game.review {
            payload["challenged_by"] = review.challengedBy.map { .string($0) }
            payload["outcome"] = review.outcome.map { .string($0) }
        }
        // Who scored, and how many: three is a field goal, whatever the write-up says yet.
        func points(_ now: String?, _ then: String?) -> WorldJSONValue? {
            guard let now = now.flatMap({ Int($0) }) else { return nil }
            let gained = now - (then.flatMap { Int($0) } ?? 0)
            return gained > 0 ? .number(Double(gained)) : nil
        }
        switch scored {
        case .team?:
            payload["scored_by"] = game.team.map { .string($0) }
            payload["points"] = points(game.teamScore, before?.teamScore)
        case .opponent?:
            payload["scored_by"] = game.opponent.map { .string($0) }
            payload["points"] = points(game.opponentScore, before?.opponentScore)
        case .both?, nil: break
        }
        // A score is a number, but for a shootout's "2(4)".
        func score(_ key: String, _ value: String?) {
            guard let value else { return }
            payload[key] = Int(value).map { .number(Double($0)) } ?? .string(value)
        }
        score("team_score", game.teamScore)
        score("opponent_score", game.opponentScore)
        // The final whistle, when the house saw it: this game turned from under way to final,
        // and Team Tracker looks every five seconds while a game is on. A final seen any other
        // way - at startup, or with the game missed - has no time it ended.
        if game.stage == .final, sameGame, before?.stage == .playing {
            payload["ended_at"] = .string(WorldJSON.timestamp(new.lastChanged))
        }
        return try WorldEventEnvelope(
            type: type,
            occurredAt: happened,
            source: EventSource(
                id: try SourceID(validating: "home-assistant:\(Self.sourceName(new.entityID))"),
                kind: HouseEvents.sourceKind, sourceEventID: key),
            subjectIDs: [mapping.subjectID],
            epistemic: EpistemicState(type: .observed, confidence: 1),
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
        case .media, .game:
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
