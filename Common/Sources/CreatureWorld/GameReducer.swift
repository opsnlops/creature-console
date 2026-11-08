import Foundation
import WorldCore

/// A team's games, from the house's Team Tracker sensor, as facts on the team (#269): the next
/// one, the one under way with its score and who has the ball, the last one final. Each time is said in words too, in the World's
/// own time zone - "Monday, November 2 at 5:15 PM" - so no mind has to make an evening out of
/// a UTC timestamp. A game moving on ends what came before it: under way, it is no longer next;
/// final, it is neither.
struct GameReducer: WorldReducer {
    let eventTypes: Set<WorldEventType> = [
        HouseEvents.gameScheduled, HouseEvents.gameStarted, HouseEvents.gameScored,
        HouseEvents.gameScoreCorrected, HouseEvents.gamePossession, HouseEvents.gameFinal,
        HouseEvents.gameReviewed, HouseEvents.gamePenalty, HouseEvents.gameFirstDown,
        HouseEvents.gamePlay,
    ]
    let zone: TimeZone

    static let producer = FactProducer(
        kind: PresenceFacts.producerKind, id: "games", version: "1")

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        guard let team = event.subjectIDs.first,
            case .string(let kickoff)? = event.payload["kickoff"],
            let kickedOff = WorldJSON.date(from: kickoff)
        else { return WorldReduction() }
        var game: [String: WorldJSONValue] = [
            "kickoff": .string(kickoff), "when": .string(Self.words(kickedOff, in: zone)),
        ]
        for key in ["team", "opponent", "home_away"] { game[key] = event.payload[key] }
        let predicate: String
        let ends: FactRetraction?
        switch event.type {
        case HouseEvents.gameScheduled:
            predicate = WorldFacts.gameNext
            ends = nil
        case HouseEvents.gameStarted, HouseEvents.gameScored, HouseEvents.gameScoreCorrected,
            HouseEvents.gamePossession, HouseEvents.gameReviewed, HouseEvents.gamePenalty,
            HouseEvents.gameFirstDown, HouseEvents.gamePlay:
            // Under way: the score and who has the ball, as of the last play the house told,
            // and the clock then.
            predicate = WorldFacts.gamePlaying
            for key in ["team_score", "opponent_score", "clock", "possession", "down_distance"] {
                game[key] = event.payload[key]
            }
            ends = ending(WorldFacts.gameNext, on: team)
        case HouseEvents.gameFinal:
            predicate = WorldFacts.gameLast
            for key in ["team_score", "opponent_score", "result"] {
                game[key] = event.payload[key]
            }
            if case .string(let endedAt)? = event.payload["ended_at"],
                let ended = WorldJSON.date(from: endedAt)
            {
                game["ended_at"] = .string(endedAt)
                game["ended"] = .string(Self.words(ended, in: zone))
            }
            ends = ending("game.", on: team, except: [WorldFacts.gameLast])
        default:
            return WorldReduction()
        }
        return WorldReduction(
            changedFacts: [
                try Fact(
                    subjectID: team,
                    predicate: predicate,
                    value: .object(game),
                    epistemic: event.epistemic,
                    validFrom: event.occurredAt,
                    derivedFrom: [.event(event.eventID)],
                    producer: Self.producer
                )
            ],
            retractions: ends.map { [$0] } ?? [])
    }

    private func ending(_ prefix: String, on team: EntityID, except: Set<String> = [])
        -> FactRetraction
    {
        FactRetraction(
            subjectID: team, predicatePrefix: prefix, except: except, producer: Self.producer,
            bases: [.observed])
    }

    /// "Monday, November 2 at 5:15 PM", where the house is.
    static func words(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return formatter.string(from: date)
    }
}
