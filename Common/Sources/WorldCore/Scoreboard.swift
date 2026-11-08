import Foundation

/// The scoreboard the World keeps for a game under way (#287). April: "What I'm picturing is
/// having the server keep track of the score, what the down counter is, where the bar is,
/// etc." Read from ESPN's down ("3rd & 15 at ARI 34") and the two sides' short names, which
/// the downs share with the sensor: the down, yards to go, where the ball is, how far it is
/// from the end zone, and where the line to gain is.
public struct Scoreboard: Equatable, Sendable {
    public var down: Int
    /// Yards to go; nil when it is goal to go.
    public var toGo: Int?
    /// Where the ball is, as ESPN says it: "ARI 34", or "50".
    public var ballOn: String
    /// From the side with the ball: how far to the end zone, and the line to gain ("ARI 19";
    /// nil when it is goal to go). Nil when the spot is on neither side's half by name.
    public var yardsToEndZone: Int?
    public var lineToGain: String?

    /// `down` as ESPN writes it - "3rd & 15 at ARI 34", "1st & Goal at SEA 6", "4th & 1 at
    /// 50" - with the short names of the side with the ball and the side without.
    public init?(down text: String, offense: String?, defense: String?) {
        let parts = text.components(separatedBy: " at ")
        guard parts.count == 2 else { return nil }
        let call = parts[0].components(separatedBy: " & ")
        guard call.count == 2, let down = Int(call[0].prefix { $0.isNumber }),
            (1...4).contains(down)
        else { return nil }
        self.down = down
        toGo = Int(call[1].trimmingCharacters(in: .whitespaces))
        ballOn = parts[1].trimmingCharacters(in: .whitespaces)
        let spot = ballOn.split(separator: " ")
        let yards: Int?
        switch spot.count {
        case 1:
            yards = spot[0] == "50" ? 50 : nil
        case 2:
            guard let line = Int(spot[1]) else { return nil }
            let side = String(spot[0])
            yards = side == offense ? 100 - line : side == defense ? line : nil
        default:
            return nil
        }
        yardsToEndZone = yards
        guard let toGo, let yards, let offense, let defense else { return }
        // The line to gain, counted back from the end zone.
        let target = yards - toGo
        lineToGain =
            target <= 0
            ? nil
            : target < 50
                ? "\(defense) \(target)" : target == 50 ? "50" : "\(offense) \(100 - target)"
    }

    /// From a game event's payload: its down, and the short name of the side with the ball
    /// and the other one. Nil when it has no down, or nobody is named with the ball.
    public init?(_ payload: [String: WorldJSONValue]) {
        func text(_ key: String) -> String? {
            if case .string(let value)? = payload[key], !value.isEmpty { return value }
            return nil
        }
        guard let down = text("down_distance"), let holder = text("possession") else {
            return nil
        }
        let (offense, defense) =
            holder == text("team")
            ? (text("team_abbr"), text("opponent_abbr"))
            : holder == text("opponent") ? (text("opponent_abbr"), text("team_abbr")) : (nil, nil)
        self.init(down: down, offense: offense, defense: defense)
    }

    /// The scoreboard as facts keep it.
    public var fields: [String: WorldJSONValue] {
        var fields: [String: WorldJSONValue] = [
            "down": .number(Double(down)), "ball_on": .string(ballOn),
        ]
        fields["to_go"] = toGo.map { .number(Double($0)) } ?? .string("goal")
        fields["yards_to_end_zone"] = yardsToEndZone.map { .number(Double($0)) }
        fields["line_to_gain"] = lineToGain.map { .string($0) }
        return fields
    }

    /// "3rd and 15 at the ARI 34, 34 yards from the end zone, the line to gain at the ARI 19";
    /// goal to go says so.
    public var words: String {
        let ordinal = ["1st", "2nd", "3rd", "4th"][down - 1]
        var line = "\(ordinal) and \(toGo.map(String.init) ?? "goal") at the \(ballOn)"
        if let yardsToEndZone { line += ", \(yardsToEndZone) yards from the end zone" }
        if let lineToGain { line += ", the line to gain at the \(lineToGain)" }
        return line
    }
}
