import Foundation
import Testing

@testable import WorldCore

/// The game so far in a stage note (#287), from the drive that ended in the 11-08 field goal:
/// the house's own events, as they reached the World.
@Suite("The game so far, for a stage note")
struct GameStoryTests {
    private let team = try! EntityID(validating: "team:seahawks")
    private let kickoff = "2026-11-08T21:25:00.000Z"
    private let start = Date(timeIntervalSince1970: 1_794_179_582)  // 2026-11-08T23:13:02Z

    @Test("A field goal reads with the down it came from, the plays before it, and its drive")
    func fieldGoalDrive() throws {
        let drive: [WorldEventEnvelope] = [
            try event(
                HouseEvents.gamePossession, at: 0, "Seattle Seahawks", "1st & 10 at SEA 16",
                "11:25 - 3rd",
                " B.Gillikin punts 50 yards to SEA 16, Center-C.Kreiter, fair catch by T.Horton."),
            try event(
                HouseEvents.gamePlay, at: 180, "Seattle Seahawks", "2nd & 9 at SEA 17",
                "11:25 - 3rd",
                " Z.Charbonnet up the middle to SEA 17 for 1 yard (J.Gibbens; A.Wingard)."),
            try event(
                HouseEvents.gameFirstDown, at: 355, "Seattle Seahawks", "1st & 10 at ARI 42",
                "9:59 - 3rd",
                " D.Lock pass short right to J.Price to ARZ 42 for 16 yards (A.Wingard; B.Baker)."),
            try event(
                HouseEvents.gamePenalty, at: 420, "Seattle Seahawks", "2nd & 16 at ARI 35",
                "5:47 - 3rd",
                " J.Price right end to ARZ 12 for 13 yards (A.Billings).\nPENALTY on SEA-E.Saubert, Offensive Holding, 10 yards, enforced at ARZ 25 - No Play."
            ),
            try event(
                HouseEvents.gamePlay, at: 801, "Seattle Seahawks", "3rd & 15 at ARI 34",
                "5:21 - 3rd",
                " (Shotgun) Z.Charbonnet left tackle to ARZ 34 for 1 yard (J.Sweat)."),
            try event(
                HouseEvents.gamePlay, at: 851, "Seattle Seahawks", "4th & 7 at ARI 26",
                "4:37 - 3rd",
                " (Shotgun) Z.Charbonnet right guard to ARZ 26 for 8 yards (Ma.Wilson; B.Baker)."),
        ]
        // The score moving before its write-up: no play of its own, and no possession.
        var kick = try event(
            HouseEvents.gameScored, at: 881, nil, "4th & 7 at ARI 26", "4:37 - 3rd", nil)
        kick.payload["scored_by"] = .string("Seattle Seahawks")
        kick.payload["points"] = .number(3)
        #expect(
            GameStory.context(of: kick, earlier: drive + [kick])
                == " This play started from 4th & 7 at ARI 26. The plays before it: (Shotgun) Z.Charbonnet left tackle to ARZ 34 for 1 yard (J.Sweat). (Shotgun) Z.Charbonnet right guard to ARZ 26 for 8 yards (Ma.Wilson; B.Baker). Seattle Seahawks' drive: 6 plays so far, since getting the ball at SEA 16 (11:25 - 3rd)."
        )
        // The 3rd-down run that set it up: run on 3rd & 15, not on the 4th & 7 that followed.
        let run = drive[5]
        #expect(
            GameStory.context(of: run, earlier: Array(drive.prefix(5))).hasPrefix(
                " This play started from 3rd & 15 at ARI 34."))
        #expect(
            GameStory.context(of: run, earlier: Array(drive.prefix(5))).hasSuffix(
                "Seattle Seahawks' drive: 5 plays so far, since getting the ball at SEA 16 (11:25 - 3rd)."
            ))
        // A change of hands starts a drive: the plays before it, nothing of a drive or a down.
        let punt = try event(
            HouseEvents.gamePossession, at: 1_000, "Arizona Cardinals", "1st & 10 at ARI 22",
            "15:00 - 4th", "J.Myers kicks 60 yards.")
        let afterPunt = GameStory.context(of: punt, earlier: drive)
        #expect(afterPunt.hasPrefix(" The plays before it:"))
        #expect(!afterPunt.contains("drive"))
        // Nothing earlier, or another game's plays: nothing to add.
        #expect(GameStory.context(of: kick, earlier: []).isEmpty)
        var other = drive[1]
        other.payload["kickoff"] = .string("2026-11-03T01:15:00.000Z")
        #expect(GameStory.context(of: kick, earlier: [other]).isEmpty)
    }

    private func event(
        _ type: WorldEventType, at offset: TimeInterval, _ possession: String?, _ down: String?,
        _ clock: String, _ play: String?
    ) throws -> WorldEventEnvelope {
        var payload: [String: WorldJSONValue] = [
            "kickoff": .string(kickoff), "team": .string("Seattle Seahawks"),
            "opponent": .string("Arizona Cardinals"), "clock": .string(clock),
        ]
        payload["possession"] = possession.map { .string($0) }
        payload["down_distance"] = down.map { .string($0) }
        payload["last_play"] = play.map { .string($0) }
        return try WorldEventEnvelope(
            type: type, occurredAt: start.addingTimeInterval(offset),
            source: EventSource(
                id: SourceID(validating: "home-assistant:sensor-seattle-seahawks"),
                kind: "home-assistant", sourceEventID: "context:\(UUID().uuidString)"),
            subjectIDs: [team], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: payload)
    }
}
