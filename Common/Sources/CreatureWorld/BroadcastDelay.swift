import Foundation
import WorldCore

/// The game as April sees it (#288). The house hears each play from ESPN's data feed, and
/// her TV stream runs behind it; on 2026-11-08 the birds were remarking on plays about 15 s
/// before YouTube TV showed them. April tells a bird how far behind the TV is, the bird keeps
/// `house.games_delay`, and for the rest of the day every game event the house sends waits
/// that long before the World takes it in.
///
/// The hold is a world timer, so it outlives a restart. Holding the whole event, not only its
/// scene, is what keeps the score from spoiling: `game.playing` moves only once the event is
/// released, so a bird asked "what's the score?" in the meantime knows only what April has
/// seen. The record stays true - the released event keeps ESPN's `occurred_at` - and carries
/// `held_seconds`, so the Viewer shows the lag and the scene opener knows it is still news.
enum BroadcastDelay {
    /// A held game event's timer. It fires as the event it holds, never as an event of its own.
    static let purpose = WorldEventType(rawValue: "game.held")!
    /// Longer than any TV stream runs behind; a bird mishearing "15 minutes" must not hold the
    /// game for a quarter of an hour.
    static let maximumSeconds: TimeInterval = 120

    /// The delay a fact asks for: a number of seconds, or words beginning with one ("15",
    /// "15 seconds"). Nil when there is none, it was ended, or it is not a positive number.
    static func seconds(in fact: Fact?) -> TimeInterval? {
        let seconds: Double? =
            switch fact?.value {
            case .number(let value)?: value
            case .string(let words)?:
                Double(
                    words.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber || $0 == "." })
            default: nil
            }
        guard let seconds, seconds >= 1 else { return nil }
        return min(seconds, maximumSeconds)
    }

    /// Holds `event` for April's TV when it is a game's and a delay is in force on the house:
    /// scheduled, and told back as held. Nil when it goes straight in - not a game event, no
    /// delay, or one the World already has, which is the duplicate it always was.
    static func hold(
        _ event: WorldEventEnvelope, house: EntityID, facts: FactRepository,
        events: WorldEventRepository, now: Date,
        schedule: (WorldTimer) async throws -> Void
    ) async throws -> WorldEventAcceptance? {
        guard HouseEvents.games.contains(event.type),
            let seconds = seconds(
                in: try await facts.fact(of: house, WorldFacts.gamesDelay, at: now)),
            try await events.event(withID: event.eventID) == nil
        else { return nil }
        try await schedule(try timer(holding: event, for: seconds, now: now))
        return WorldEventAcceptance(disposition: .held, event: event)
    }

    /// The timer holding `event` for `seconds` from `now`. Named by the event, so the house
    /// sending it again while it waits holds it once.
    static func timer(holding event: WorldEventEnvelope, for seconds: TimeInterval, now: Date)
        throws -> WorldTimer
    {
        let held = try WorldJSON.makeDecoder().decode(
            WorldJSONValue.self, from: WorldJSON.makeEncoder().encode(event))
        return WorldTimer(
            timerID: try TimerID(
                validating: "timer:game-held:\(event.eventID.rawValue.lowercased())"),
            purpose: purpose,
            dueAt: now.addingTimeInterval(seconds),
            subjectIDs: event.subjectIDs,
            causedBy: [],
            payload: [
                "event": held, "event_type": .string(event.type.rawValue),
                "held_seconds": .number(seconds),
            ])
    }

    /// The event a hold releases, as the house sent it, with how long it was held.
    static func released(from timer: WorldTimer) throws -> WorldEventEnvelope {
        guard let held = timer.payload["event"] else { throw BroadcastDelayError.nothingHeld }
        var event = try WorldJSON.makeDecoder().decode(
            WorldEventEnvelope.self, from: WorldJSON.makeEncoder().encode(held))
        event.payload["held_seconds"] = timer.payload["held_seconds"]
        return event
    }
}

enum BroadcastDelayError: Error, Equatable, Sendable {
    case nothingHeld
}
