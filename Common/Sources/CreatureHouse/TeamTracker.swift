import Foundation
import WorldCore

/// A team's game, as Home Assistant's Team Tracker sensor shows it (#269): one game at a time -
/// the last one, final, until the next is twelve hours away, then that one. Read as its source
/// writes it, not as its README says: ESPN's states upper-cased, the kickoff with no seconds
/// (`2026-11-03T01:15Z`), the scores as strings (`"20"`, `"2(4)"` after a shootout).
struct TeamTrackerGame: Equatable, Sendable {
    enum Stage: String, Sendable {
        case scheduled = "PRE"
        case playing = "IN"
        case final = "POST"
    }

    var stage: Stage
    /// Which game this is: a game moved to another time is told again, as another.
    var kickoff: Date
    var team: String?
    var opponent: String?
    /// `home` or `away`.
    var homeAway: String?
    /// The scores, once the game is under way.
    var teamScore: String?
    var opponentScore: String?
    /// While it is under way: the game's clock ("7:12 - 2nd") and the last play, in ESPN's words.
    var clock: String?
    var lastPlay: String?
    /// While it is under way, who has the ball - the team's name or the opponent's - and where:
    /// ESPN's down and distance ("1st & 10 at SEA 25"). Nil between plays when ESPN says
    /// nothing, which is not the ball changing hands.
    var possession: String?
    var downDistance: String?
    /// ESPN's short names for the two sides ("SEA", "ARI"), which its play-by-play uses for
    /// who a flag is on - though not always: the Cardinals are `ARI` here and `ARZ` in the plays.
    var teamAbbreviation: String?
    var opponentAbbreviation: String?
    /// `won`, `lost` or `tied`, once it is final.
    var result: String?

    /// The game the sensor shows; nil for a bye, nothing found, or a sensor that is gone - and
    /// for a state with no kickoff, which is no game to speak of.
    init?(_ state: EntityState) {
        guard let stage = Stage(rawValue: state.state),
            case .string(let date)? = state.attributes["date"],
            let kickoff = Self.date(date)
        else { return nil }
        func text(_ key: String) -> String? {
            switch state.attributes[key] {
            case .string(let value)? where !value.isEmpty: value
            case .number(let value)?: value.rounded() == value ? String(Int(value)) : String(value)
            default: nil
            }
        }
        self.stage = stage
        self.kickoff = kickoff
        team = text("team_long_name") ?? text("team_name")
        opponent = text("opponent_long_name") ?? text("opponent_name")
        homeAway = text("team_homeaway")
        guard stage != .scheduled else { return }
        teamScore = text("team_score")
        opponentScore = text("opponent_score")
        guard stage == .final else {
            clock = text("clock")
            lastPlay = text("last_play")
            // ESPN names the side with the ball by its team id.
            if let side = Self.side(in: state) {
                possession =
                    side == text("team_id") ? team : side == text("opponent_id") ? opponent : nil
            }
            downDistance = text("down_distance_text")
            teamAbbreviation = text("team_abbr")
            opponentAbbreviation = text("opponent_abbr")
            return
        }
        result = Self.result(
            team: Self.flag(state.attributes["team_winner"]),
            opponent: Self.flag(state.attributes["opponent_winner"]),
            scores: (teamScore.flatMap { Int($0) }, opponentScore.flatMap { Int($0) }))
    }

    /// ESPN's id for the side with the ball, as the sensor says it; nil when it says nothing.
    static func side(in state: EntityState) -> String? {
        switch state.attributes["possession"] {
        case .string(let id)? where !id.isEmpty: id
        case .number(let id)?: String(Int(id))
        default: nil
        }
    }

    /// Who scored since `before`, the same game under way: the team, the opponent, or - both
    /// having moved between two looks - both. Nil when no score went up: a correction taking
    /// points away is the score, not a score.
    func scored(since before: TeamTrackerGame) -> Scored? {
        func up(_ now: String?, _ then: String?) -> Bool {
            guard let now = now.flatMap({ Int($0) }) else { return false }
            return now > (then.flatMap { Int($0) } ?? 0)
        }
        switch (up(teamScore, before.teamScore), up(opponentScore, before.opponentScore)) {
        case (true, true): return .both
        case (true, false): return .team
        case (false, true): return .opponent
        case (false, false): return nil
        }
    }

    enum Scored: Sendable { case team, opponent, both }

    // MARK: - Plays (#287)

    /// The down is a first: "1st & 10 at SEA 25", "1st & Goal at ARI 6".
    var isFirstDown: Bool { downDistance?.hasPrefix("1st ") == true }

    /// A foul the officials enforced on the last play, as ESPN writes it up:
    /// "PENALTY on CHI-J.Lynch, Roughing the Passer, 15 yards, enforced at SEA 24 - No Play."
    struct Penalty: Equatable, Sendable {
        /// The side it was on: the team's or opponent's name when ESPN's short name matches
        /// theirs, otherwise ESPN's short name as written ("ARZ").
        var on: String
        var foul: String
        var yards: Int?
    }

    /// The first enforced foul in the last play; nil when there is none, when every flag was
    /// declined, or when they offset - a flag that changes nothing is not news. This reads
    /// ESPN's fixed format; what the foul means is for the minds.
    var penalty: Penalty? {
        guard let play = lastPlay, !play.localizedCaseInsensitiveContains("offset") else {
            return nil
        }
        for segment in play.components(separatedBy: "PENALTY on ").dropFirst() {
            let parts = segment.components(separatedBy: ", ")
            guard parts.count >= 2 else { continue }
            let rest = parts.dropFirst(2).joined(separator: ", ")
            if rest.lowercased().hasPrefix("declined") { continue }
            let who = parts[0]
            let side = who.split(separator: "-", maxSplits: 1).first.map(String.init) ?? who
            let foul = parts[1].trimmingCharacters(in: .whitespaces)
            guard !side.isEmpty, !foul.isEmpty else { continue }
            let named =
                side == teamAbbreviation
                ? team : side == opponentAbbreviation ? opponent : nil
            let yards = parts.dropFirst(2).first.flatMap { part -> Int? in
                let words = part.split(separator: " ")
                guard words.count == 2, words[1].hasPrefix("yard") else { return nil }
                return Int(words[0])
            }
            return Penalty(on: named ?? side, foul: foul, yards: yards)
        }
        return nil
    }

    /// A replay review the last play came out of: a coach's challenge ("SEATTLE challenged the
    /// pass completion ruling, and the play was REVERSED.") or the booth's ("The Replay
    /// Official reviewed ..."). ESPN writes it up only once it is decided.
    struct Review: Equatable, Sendable {
        /// Who asked for it, as ESPN writes it ("SEATTLE"); nil for the booth.
        var challengedBy: String?
        /// `reversed`, `upheld` or `stands`; nil when ESPN does not say.
        var outcome: String?
    }

    var review: Review? {
        guard let play = lastPlay else { return nil }
        var challenger: String?
        if let range = play.range(of: " challenged ") {
            // The words before it, back to the start of that sentence or a parenthesis.
            let before = play[..<range.lowerBound]
            let start =
                before.lastIndex(where: { ".()\n".contains($0) })
                .map { before.index(after: $0) } ?? before.startIndex
            let name = before[start...].trimmingCharacters(in: .whitespaces)
            challenger = name.isEmpty ? nil : name
        } else if !play.localizedCaseInsensitiveContains("Replay Official")
            && !play.localizedCaseInsensitiveContains("Replay Assistant")
        {
            return nil
        }
        let outcome: String? =
            if play.localizedCaseInsensitiveContains("reversed") {
                "reversed"
            } else if play.localizedCaseInsensitiveContains("upheld")
                || play.localizedCaseInsensitiveContains("confirmed")
            {
                "upheld"
            } else if play.localizedCaseInsensitiveContains("stands") {
                "stands"
            } else {
                nil
            }
        return Review(challengedBy: challenger, outcome: outcome)
    }

    /// Who won: the winner flags, and the scores where the flags are missing. Neither the
    /// winner is a tie.
    static func result(team: Bool?, opponent: Bool?, scores: (Int?, Int?)) -> String? {
        switch (team, opponent) {
        case (true?, _): return "won"
        case (_, true?): return "lost"
        case (false?, false?): return "tied"
        default:
            guard let ours = scores.0, let theirs = scores.1 else { return nil }
            return ours > theirs ? "won" : ours < theirs ? "lost" : "tied"
        }
    }

    /// A winner flag: a bool, or - from some APIs - the word.
    static func flag(_ value: WorldJSONValue?) -> Bool? {
        switch value {
        case .bool(let flag)?: flag
        case .string("true")?: true
        case .string("false")?: false
        default: nil
        }
    }

    /// ESPN's kickoff: to the minute, or a full timestamp.
    static func date(_ raw: String) -> Date? {
        if let date = WorldJSON.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return formatter.date(from: raw)
    }
}
