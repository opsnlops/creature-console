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
            if let side = text("possession") {
                possession =
                    side == text("team_id") ? team : side == text("opponent_id") ? opponent : nil
            }
            downDistance = text("down_distance_text")
            return
        }
        result = Self.result(
            team: Self.flag(state.attributes["team_winner"]),
            opponent: Self.flag(state.attributes["opponent_winner"]),
            scores: (teamScore.flatMap { Int($0) }, opponentScore.flatMap { Int($0) }))
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
