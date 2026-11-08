import Foundation
import Testing

@testable import WorldCore

/// The scoreboard the World keeps (#287), from the downs ESPN gave during Seahawks–Cardinals on
/// 2026-11-08. April: "having the server keep track of the score, what the down counter is,
/// where the bar is."
@Suite("The scoreboard, from ESPN's downs")
struct ScoreboardTests {
    @Test("Down, yards to go, the ball, the end zone and the line to gain, from either side")
    func downs() throws {
        func board(_ down: String, _ offense: String = "SEA", _ defense: String = "ARI")
            throws -> Scoreboard
        {
            try #require(Scoreboard(down: down, offense: offense, defense: defense))
        }
        let third = try board("3rd & 15 at ARI 34")
        #expect(third.down == 3)
        #expect(third.toGo == 15)
        #expect(third.ballOn == "ARI 34")
        #expect(third.yardsToEndZone == 34)
        #expect(third.lineToGain == "ARI 19")
        #expect(
            third.words
                == "3rd and 15 at the ARI 34, 34 yards from the end zone, the line to gain at the ARI 19"
        )
        // On their own half: the end zone is the far one.
        let own = try board("1st & 10 at SEA 16")
        #expect(own.yardsToEndZone == 84)
        #expect(own.lineToGain == "SEA 26")
        // A line to gain across midfield, and on it.
        #expect(try board("2nd & 5 at SEA 45").lineToGain == "50")
        #expect(try board("4th & 1 at 50").lineToGain == "ARI 49")
        #expect(try board("2nd & 10 at SEA 45").lineToGain == "ARI 45")
        // Arizona with the ball.
        let theirs = try board("1st & 10 at ARI 22", "ARI", "SEA")
        #expect(theirs.yardsToEndZone == 78)
        #expect(theirs.lineToGain == "ARI 32")
        // Goal to go: no line but the goal line.
        let goal = try board("1st & Goal at ARI 7")
        #expect(goal.toGo == nil)
        #expect(goal.yardsToEndZone == 7)
        #expect(goal.lineToGain == nil)
        #expect(goal.words == "1st and goal at the ARI 7, 7 yards from the end zone")
        // A short name that is neither side's: the ball is where ESPN says, and no more.
        let unknown = try board("3rd & 17 at ARZ 15")
        #expect(unknown.yardsToEndZone == nil)
        #expect(unknown.lineToGain == nil)
        // Not a down at all.
        #expect(Scoreboard(down: "Official Timeout", offense: "SEA", defense: "ARI") == nil)
    }

    @Test("From an event: the side with the ball by name, and a stage note that says it all")
    func fromAnEvent() throws {
        let payload: [String: WorldJSONValue] = [
            "team": .string("Seattle Seahawks"), "opponent": .string("Arizona Cardinals"),
            "team_abbr": .string("SEA"), "opponent_abbr": .string("ARI"),
            "possession": .string("Seattle Seahawks"),
            "down_distance": .string("4th & 7 at ARI 26"),
            "team_score": .number(14), "opponent_score": .number(3), "clock": .string("4:37 - 3rd"),
            "team_timeouts": .number(2), "opponent_timeouts": .number(3),
            "kickoff": .string("2026-11-08T21:25:00.000Z"),
            "last_play": .string(" (Shotgun) Z.Charbonnet right guard to ARZ 26 for 8 yards."),
        ]
        let board = try #require(Scoreboard(payload))
        #expect(board.fields["down"] == .number(4))
        #expect(board.fields["to_go"] == .number(7))
        #expect(board.fields["yards_to_end_zone"] == .number(26))
        #expect(board.fields["line_to_gain"] == .string("ARI 19"))
        let seahawks = try EntityID(validating: "team:seahawks")
        let event = try WorldEventEnvelope(
            type: HouseEvents.gamePlay, occurredAt: Date(),
            source: EventSource(
                id: SourceID(validating: "home-assistant:sensor-seattle-seahawks"),
                kind: "home-assistant", sourceEventID: "context:x"),
            subjectIDs: [seahawks], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: payload)
        #expect(
            SceneOpeningPolicy.gameText(event)
                == "The next play in the game between Seattle Seahawks, the team April follows, and Arizona Cardinals: Seattle Seahawks 14, Arizona Cardinals 3 (4:37 - 3rd). Next: Seattle Seahawks have it, 4th and 7 at the ARI 26, 26 yards from the end zone, the line to gain at the ARI 19. Timeouts left: Seattle Seahawks 2, Arizona Cardinals 3. The play: (Shotgun) Z.Charbonnet right guard to ARZ 26 for 8 yards."
        )
    }
}
