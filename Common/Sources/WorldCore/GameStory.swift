import Foundation

/// The game so far, for a stage note (#287): what a person on the couch knows that one play
/// alone doesn't say. On 2026-11-08 the birds saw each play by itself. Beaky passed on a field
/// goal that looked like the run before it, and two birds took "4th & 7" after a 3rd-down run
/// as a fourth down converted. April asked whether modeling the game would make a better show.
/// The World already has every play of the game in its record, so the note reads it from there:
/// the down this play started from, the two plays before it, and the drive so far.
public enum GameStory {
    /// Events that move a game under way, in the order the house told them.
    static let underWay: Set<WorldEventType> = [
        HouseEvents.gameStarted, HouseEvents.gameScored, HouseEvents.gameScoreCorrected,
        HouseEvents.gamePossession, HouseEvents.gameReviewed, HouseEvents.gamePenalty,
        HouseEvents.gameFirstDown, HouseEvents.gamePlay,
    ]
    /// Plays a drive is made of; a change of hands starts one, and is the other side's play.
    static let drivePlays: Set<WorldEventType> = [
        HouseEvents.gameScored, HouseEvents.gameReviewed, HouseEvents.gamePenalty,
        HouseEvents.gameFirstDown, HouseEvents.gamePlay,
    ]

    /// " This play started from 3rd & 15 at ARI 34. The plays before it: ...; .... Seattle
    /// Seahawks' drive: 6 plays so far, since getting the ball at SEA 16 (11:25 - 3rd)." Empty
    /// when the game's record says nothing more, or for a final.
    public static func context(of event: WorldEventEnvelope, earlier: [WorldEventEnvelope])
        -> String
    {
        guard underWay.contains(event.type), event.type != HouseEvents.gameStarted,
            let kickoff = text(event, "kickoff")
        else { return "" }
        let before = plays(
            in: earlier.filter {
                $0.eventID != event.eventID && underWay.contains($0.type)
                    && text($0, "kickoff") == kickoff && $0.occurredAt <= event.occurredAt
            },
            excluding: text(event, "last_play").map(key))
        guard let previous = before.last else { return "" }
        var words = ""
        // The down it was run on: the note's own down is the next one. Taken from the last
        // play that is not this one - ESPN can tell one play in two updates, and the first
        // update's down is this play's own.
        if event.type != HouseEvents.gamePossession, let down = text(previous, "down_distance") {
            words += " This play started from \(down)."
        }
        let written = before.suffix(2).compactMap { text($0, "last_play") }.map { trimmed($0) }
        if !written.isEmpty {
            words += " The plays before it: " + written.joined(separator: " ")
        }
        // The drive: back to where the side with the ball got it.
        guard event.type != HouseEvents.gamePossession,
            let side = text(event, "possession") ?? text(previous, "possession")
        else { return words }
        var count = drivePlays.contains(event.type) ? 1 : 0
        for earlier in before.reversed() {
            let holder = text(earlier, "possession")
            if earlier.type == HouseEvents.gamePossession || earlier.type == HouseEvents.gameStarted
            {
                guard holder == side, let spot = text(earlier, "down_distance") else { break }
                let at = spot.range(of: " at ").map { String(spot[$0.upperBound...]) } ?? spot
                let when = text(earlier, "clock").map { " (\($0))" } ?? ""
                let whose = side.hasSuffix("s") ? "\(side)'" : "\(side)'s"
                words +=
                    " \(whose) drive: \(count) play\(count == 1 ? "" : "s") so far, since getting the ball at \(at)\(when)."
                break
            }
            if let holder, holder != side { break }
            if drivePlays.contains(earlier.type) { count += 1 }
        }
        return words
    }

    /// One record per play, in order: ESPN tells a play in two updates when a flag or a
    /// correction follows it, and both reached the World (on 11-08 an incomplete pass was
    /// "the plays before it" twice). Consecutive records with the same write-up are one play,
    /// told by the later; the play being told now is left out wherever it appears.
    static func plays(in events: [WorldEventEnvelope], excluding current: String?)
        -> [WorldEventEnvelope]
    {
        var plays: [WorldEventEnvelope] = []
        for event in events {
            let written = text(event, "last_play").map(key)
            if let written, written == current { continue }
            if let written, let last = plays.last, text(last, "last_play").map(key) == written {
                plays[plays.count - 1] = event
            } else {
                plays.append(event)
            }
        }
        return plays
    }

    /// A write-up as a key: ESPN's spacing and line breaks differ between two updates of one
    /// play ("(A.Billings).\nPENALTY" and "(A.Billings).PENALTY", " D.Lock" and "D.Lock").
    /// The house compares by it too, so a second update of the same play is not a new play.
    public static func key(_ play: String) -> String {
        String(play.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    private static func text(_ event: WorldEventEnvelope, _ key: String) -> String? {
        switch event.payload[key] {
        case .string(let value)? where !value.trimmingCharacters(in: .whitespaces).isEmpty: value
        case .number(let value)?: String(Int(value))
        default: nil
        }
    }

    /// One write-up as one sentence: ESPN's own line breaks and leading spaces out.
    private static func trimmed(_ play: String) -> String {
        let line = play.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.joined(separator: " ")
        return line.hasSuffix(".") ? line : line + "."
    }
}
