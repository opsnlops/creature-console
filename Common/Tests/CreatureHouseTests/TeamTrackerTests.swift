import Foundation
import Testing
import WorldCore

@testable import creature_house

/// Team Tracker's sensor as its source writes it (#269): ESPN's states upper-cased, a kickoff
/// with no seconds, scores as strings, and the winner as a bool only once it is final. The game
/// is the Seahawks' home win over the Chiefs on 2026-10-25.
@Suite("A team's games, translated")
struct TeamTrackerTests {
    private let seahawks = try! EntityID(validating: "team:seahawks")
    private let kickoff = "2026-10-26T00:20Z"
    private let kickedOff = Date(timeIntervalSince1970: 1_792_974_000)  // 2026-10-26T00:20:00Z
    private var translator: HouseTranslator {
        HouseTranslator(mappings: [
            EntityMapping(entityID: "sensor.seattle_seahawks", subjectID: seahawks, kind: .game)
        ])
    }

    @Test(
        "Published, under way, final: one event each, about the team, and the final has its whistle"
    )
    func aGameSeenThrough() async throws {
        let announcer = HouseAnnouncer(translator: translator)
        let published = try await announcer.events(
            from: nil, to: sensor("PRE", at: -3_600, ["odds": .string("SEA -1.5")]))
        let scheduled = try #require(published.only)
        #expect(scheduled.type == HouseEvents.gameScheduled)
        #expect(scheduled.subjectIDs == [seahawks])
        #expect(scheduled.placeID == nil)
        #expect(scheduled.source.id.rawValue == "home-assistant:sensor-seattle-seahawks")
        #expect(scheduled.source.sourceEventID == "game:2026-10-26T00:20:00.000Z:scheduled")
        #expect(scheduled.payload["kickoff"] == .string("2026-10-26T00:20:00.000Z"))
        #expect(scheduled.payload["team"] == .string("Seattle Seahawks"))
        #expect(scheduled.payload["opponent"] == .string("Kansas City Chiefs"))
        #expect(scheduled.payload["home_away"] == .string("home"))
        #expect(scheduled.payload["team_score"] == nil)
        #expect(scheduled.payload["result"] == nil)

        // The odds and the countdown move every few minutes; that is not news.
        #expect(
            try await announcer.events(
                from: nil,
                to: sensor("PRE", at: -1_800, ["odds": .string("SEA -2.5")])
            ).isEmpty)

        let started = try #require(
            try await announcer.events(
                from: nil, to: sensor("IN", at: 0, ["clock": .string("15:00 - 1st")])
            )
            .only)
        #expect(started.type == HouseEvents.gameStarted)
        #expect(started.source.sourceEventID == "game:2026-10-26T00:20:00.000Z:started")
        #expect(
            try await announcer.events(
                from: nil, to: sensor("IN", at: 1_800, ["clock": .string("7:12 - 2nd")])
            ).isEmpty)

        // The whistle: Team Tracker looks every five seconds during a game, so the moment it
        // turned final is when the game ended.
        let whistle = kickedOff.addingTimeInterval(11_472)
        let final = try #require(
            try await announcer.events(from: nil, to: sensor("POST", at: 11_472, finished)).only)
        #expect(final.type == HouseEvents.gameFinal)
        #expect(final.occurredAt == whistle)
        #expect(final.source.sourceEventID == "game:2026-10-26T00:20:00.000Z:final")
        #expect(final.payload["team_score"] == .number(20))
        #expect(final.payload["opponent_score"] == .number(3))
        #expect(final.payload["result"] == .string("won"))
        #expect(final.payload["ended_at"] == .string(WorldJSON.timestamp(whistle)))
        #expect(final.epistemic.type == .observed)
    }

    @Test(
        "A final first seen at startup fills the blank under the live final's key, with no whistle")
    func snapshotFinal() throws {
        let snapshot = try #require(
            try translator.events(from: nil, to: sensor("POST", at: 86_400, finished)).only)
        #expect(snapshot.type == HouseEvents.gameFinal)
        #expect(snapshot.source.sourceEventID == "game:2026-10-26T00:20:00.000Z:final")
        #expect(snapshot.payload["result"] == .string("won"))
        #expect(snapshot.payload["ended_at"] == nil)

        // Missed the game entirely: from published straight to final is no whistle either.
        let missed = try #require(
            try translator.events(
                from: sensor("PRE", at: -3_600), to: sensor("POST", at: 86_400, finished)
            ).only)
        #expect(missed.payload["ended_at"] == nil)
    }

    @Test("Home Assistant restarting is not a second final")
    func goneAndBack() async throws {
        let announcer = HouseAnnouncer(translator: translator)
        _ = try await announcer.events(from: nil, to: sensor("POST", at: 11_472, finished))
        #expect(
            try await announcer.events(
                from: nil,
                to: EntityState(
                    entityID: "sensor.seattle_seahawks", state: "unavailable", attributes: [:],
                    lastChanged: kickedOff.addingTimeInterval(40_000))
            ).isEmpty)
        // Back, the same final, changed just now as far as Home Assistant knows.
        #expect(
            try await announcer.events(from: nil, to: sensor("POST", at: 40_060, finished)).isEmpty)
    }

    @Test("The next game published is news; so is the same game moved to another kickoff")
    func theNextGame() throws {
        let bears: [String: WorldJSONValue] = [
            "date": .string("2026-11-03T01:15Z"),
            "opponent_long_name": .string("Chicago Bears"),
        ]
        let next = try #require(
            try translator.events(
                from: sensor("POST", at: 11_472, finished),
                to: sensor("PRE", at: 600_000, bears)
            ).only)
        #expect(next.type == HouseEvents.gameScheduled)
        #expect(next.payload["kickoff"] == .string("2026-11-03T01:15:00.000Z"))
        #expect(next.payload["opponent"] == .string("Chicago Bears"))

        var moved = bears
        moved["date"] = .string("2026-11-03T21:25Z")
        let flexed = try #require(
            try translator.events(
                from: sensor("PRE", at: 600_000, bears), to: sensor("PRE", at: 600_100, moved)
            ).only)
        #expect(flexed.source.sourceEventID == "game:2026-11-03T21:25:00.000Z:scheduled")
    }

    @Test("A bye, nothing found, a dead sensor, and a state with no kickoff are no game")
    func noGame() throws {
        for state in ["BYE", "NOT_FOUND", "unavailable", "unknown"] {
            #expect(try translator.events(from: nil, to: sensor(state, at: 0)).isEmpty)
        }
        #expect(
            try translator.events(
                from: nil,
                to: EntityState(
                    entityID: "sensor.seattle_seahawks", state: "PRE",
                    attributes: ["team_long_name": .string("Seattle Seahawks")],
                    lastChanged: kickedOff)
            ).isEmpty)
    }

    @Test("The result: the winner flags, the word for them, or the scores; neither winner is a tie")
    func results() throws {
        #expect(TeamTrackerGame.result(team: true, opponent: false, scores: (nil, nil)) == "won")
        #expect(TeamTrackerGame.result(team: false, opponent: true, scores: (nil, nil)) == "lost")
        #expect(TeamTrackerGame.result(team: false, opponent: false, scores: (20, 20)) == "tied")
        #expect(TeamTrackerGame.result(team: nil, opponent: nil, scores: (17, 20)) == "lost")
        #expect(TeamTrackerGame.result(team: nil, opponent: nil, scores: (nil, 20)) == nil)
        #expect(TeamTrackerGame.flag(.string("true")) == true)
        #expect(TeamTrackerGame.flag(.string("false")) == false)
        #expect(TeamTrackerGame.flag(.null) == nil)

        var lost = finished
        lost["team_score"] = .string("17")
        lost["opponent_score"] = .string("20")
        lost["team_winner"] = .string("false")
        lost["opponent_winner"] = .string("true")
        let event = try #require(
            try translator.events(from: nil, to: sensor("POST", at: 11_000, lost)).only)
        #expect(event.payload["result"] == .string("lost"))

        // A shootout's score is the score as written.
        var shootout = finished
        shootout["team_score"] = .string("2(4)")
        let penalties = try #require(
            try translator.events(from: nil, to: sensor("POST", at: 11_000, shootout)).only)
        #expect(penalties.payload["team_score"] == .string("2(4)"))
    }

    @Test("ESPN's kickoff to the minute and a full timestamp both read")
    func kickoffs() {
        #expect(TeamTrackerGame.date("2026-10-26T00:20Z") == kickedOff)
        #expect(TeamTrackerGame.date("2026-10-26T00:20:00Z") == kickedOff)
        #expect(TeamTrackerGame.date("2026-10-26T00:20:00.000Z") == kickedOff)
        #expect(TeamTrackerGame.date("Sunday") == nil)
    }

    @Test("A house file maps a Team Tracker sensor as a game")
    func configuration() throws {
        let raw = try JSONDecoder().decode(
            EntityMapping.Raw.self,
            from: Data(
                #"{ "entity_id": "sensor.seattle_seahawks", "subject_id": "team:seahawks", "kind": "game" }"#
                    .utf8))
        let mapping = try EntityMapping(raw: raw)
        #expect(mapping.kind == .game)
        #expect(mapping.subjectID == seahawks)
    }

    @Test(
        "Under way, each score is news, keyed by the change: a correction, and a score back again")
    func scores() async throws {
        let announcer = HouseAnnouncer(translator: translator)
        func live(_ offset: TimeInterval, _ ours: Int, _ theirs: Int, clock: String = "7:12 - 2nd")
            async throws -> [WorldEventEnvelope]
        {
            try await announcer.events(
                from: nil,
                to: sensor(
                    "IN", at: offset, changed: 0,
                    [
                        "team_score": .string("\(ours)"), "opponent_score": .string("\(theirs)"),
                        "clock": .string(clock), "last_play": .string("play at \(Int(offset))"),
                    ]))
        }
        let started = try #require(try await live(0, 0, 0, clock: "15:00 - 1st").only)
        #expect(started.type == HouseEvents.gameStarted)
        #expect(started.payload["team_score"] == .number(0))
        // The clock runs; nobody scores.
        #expect(try await live(300, 0, 0, clock: "10:01 - 1st").isEmpty)

        let touchdown = try #require(try await live(600, 6, 0).only)
        #expect(touchdown.type == HouseEvents.gameScored)
        #expect(touchdown.payload["scored_by"] == .string("Seattle Seahawks"))
        #expect(touchdown.payload["team_score"] == .number(6))
        #expect(touchdown.payload["clock"] == .string("7:12 - 2nd"))
        #expect(touchdown.payload["last_play"] == .string("play at 600"))
        #expect(touchdown.source.sourceEventID == "context:ctx-IN-600.0")
        // A score moves only the attributes: Home Assistant's `last_changed` is still kickoff's,
        // and the score happened at `last_updated` (#271).
        #expect(started.occurredAt == kickedOff)
        #expect(touchdown.occurredAt == kickedOff.addingTimeInterval(600))

        let answer = try #require(try await live(900, 6, 7).only)
        #expect(answer.payload["scored_by"] == .string("Kansas City Chiefs"))

        // Our touchdown overturned on review: points off the board, scored by nobody.
        let overturned = try #require(try await live(1_000, 0, 7).only)
        #expect(overturned.type == HouseEvents.gameScoreCorrected)
        #expect(overturned.payload["scored_by"] == nil)
        #expect(overturned.payload["team_score"] == .number(0))

        // And scored again: the same 6-7 as before, and a score all the same.
        let again = try #require(try await live(1_200, 6, 7).only)
        #expect(again.type == HouseEvents.gameScored)
        #expect(again.source.sourceEventID != answer.source.sourceEventID)

        // Both sides between two looks: a score, by nobody in particular.
        let both = try #require(try await live(1_500, 9, 10).only)
        #expect(both.type == HouseEvents.gameScored)
        #expect(both.payload["scored_by"] == nil)
    }

    @Test("Under way, the ball changing hands is news; ESPN saying nothing between plays is not")
    func possession() async throws {
        let announcer = HouseAnnouncer(translator: translator)
        func live(
            _ offset: TimeInterval, ball: String?, _ ours: Int = 0, _ theirs: Int = 0,
            down: String? = nil
        ) async throws -> [WorldEventEnvelope] {
            var attributes: [String: WorldJSONValue] = [
                "team_score": .string("\(ours)"), "opponent_score": .string("\(theirs)"),
                "clock": .string("9:41 - 1st"), "last_play": .string("play at \(Int(offset))"),
                "possession": ball.map { .string($0) } ?? .string(""),
            ]
            attributes["down_distance_text"] = down.map { .string($0) }
            return try await announcer.events(
                from: nil, to: sensor("IN", at: offset, changed: 0, attributes))
        }
        // Under way with nobody on the ball yet, then the Chiefs receive.
        #expect(try await live(0, ball: nil).only?.type == HouseEvents.gameStarted)
        let first = try #require(try await live(30, ball: "12", down: "1st & 10 at KC 25").only)
        #expect(first.type == HouseEvents.gamePossession)
        #expect(first.payload["possession"] == .string("Kansas City Chiefs"))
        #expect(first.payload["down_distance"] == .string("1st & 10 at KC 25"))
        #expect(first.occurredAt == kickedOff.addingTimeInterval(30))
        // Their downs go by: each a play (#287). ESPN saying nothing between plays is not.
        #expect(
            try await live(60, ball: "12", down: "2nd & 4 at KC 31").only?.type
                == HouseEvents.gamePlay)
        #expect(try await live(70, ball: nil).isEmpty)
        #expect(
            try await live(80, ball: "12", down: "3rd & 4 at KC 31").only?.type
                == HouseEvents.gamePlay)
        // A punt: the Seahawks have it.
        let punt = try #require(try await live(120, ball: "26", down: "1st & 10 at SEA 30").only)
        #expect(punt.type == HouseEvents.gamePossession)
        #expect(punt.payload["possession"] == .string("Seattle Seahawks"))
        // A touchdown and the kickoff in one look: the score is the news, with the ball in it.
        let score = try #require(try await live(400, ball: "12", 7, 0).only)
        #expect(score.type == HouseEvents.gameScored)
        #expect(score.payload["possession"] == .string("Kansas City Chiefs"))

        // 11-02, the Seahawks' field goal: ESPN names nobody on the scoring play, then the
        // scorers again for their kickoff. That is not the ball changing hands.
        let drive = try #require(try await live(600, ball: "26", 7, 0).only)
        #expect(drive.type == HouseEvents.gamePossession)
        let kick = try #require(try await live(700, ball: nil, 10, 0).only)
        #expect(kick.type == HouseEvents.gameScored)
        #expect(try await live(720, ball: "26", 10, 0).isEmpty)
        // The return: now it has.
        let returned = try #require(try await live(760, ball: "12", 10, 0).only)
        #expect(returned.type == HouseEvents.gamePossession)
        #expect(returned.payload["possession"] == .string("Kansas City Chiefs"))
    }

    @Test("Restarted mid-game, the house tells the game under way with its score, and no score")
    func restartedMidGame() throws {
        let started = try #require(
            try translator.events(
                from: nil,
                to: sensor(
                    "IN", at: 4_000,
                    ["team_score": .string("14"), "opponent_score": .string("10")])
            ).only)
        #expect(started.type == HouseEvents.gameStarted)
        #expect(started.payload["team_score"] == .number(14))
    }

    // MARK: -

    /// Team Tracker's attributes once the game is over, as its source sets them.
    private var finished: [String: WorldJSONValue] {
        [
            "team_score": .string("20"), "opponent_score": .string("3"),
            "team_winner": .bool(true), "opponent_winner": .bool(false),
        ]
    }

    /// Team Tracker's sensor as Home Assistant sends it: updated at `offset`, and changed - its
    /// state, not its attributes - at `changed`, which is the same moment unless said otherwise.
    @Test("Under way, a play, a first down, a flag and a review's ruling: one piece of news a play")
    func plays() async throws {
        let announcer = HouseAnnouncer(translator: translator)
        func live(_ offset: TimeInterval, play: String, down: String, ball: String = "12")
            async throws -> [WorldEventEnvelope]
        {
            try await announcer.events(
                from: nil,
                to: sensor(
                    "IN", at: offset, changed: 0,
                    [
                        "team_score": .string("0"), "opponent_score": .string("0"),
                        "clock": .string("9:41 - 1st"), "last_play": .string(play),
                        "possession": .string(ball), "down_distance_text": .string(down),
                        "opponent_abbr": .string("KC"),
                    ]))
        }
        _ = try await announcer.events(
            from: nil,
            to: sensor(
                "IN", at: 0, ["team_score": .string("0"), "opponent_score": .string("0")]))
        #expect(
            try await live(30, play: "Kickoff", down: "1st & 10 at KC 25").only?.type
                == HouseEvents.gamePossession)
        // A down going by is a play; the down back to a first, for the same side, a first down.
        let run = try #require(
            try await live(60, play: "Run for 6 yards", down: "2nd & 4 at KC 31").only)
        #expect(run.type == HouseEvents.gamePlay)
        #expect(run.payload["last_play"] == .string("Run for 6 yards"))
        let first = try #require(
            try await live(90, play: "Pass for 10 yards", down: "1st & 10 at KC 41").only)
        #expect(first.type == HouseEvents.gameFirstDown)
        #expect(first.payload["possession"] == .string("Kansas City Chiefs"))
        #expect(first.payload["down_distance"] == .string("1st & 10 at KC 41"))
        #expect(first.source.sourceEventID == "context:ctx-IN-90.0")
        // The same look again, the clock moving, is not.
        #expect(try await live(95, play: "Pass for 10 yards", down: "1st & 10 at KC 41").isEmpty)
        // The write-up and the down can arrive in separate looks: still one first down, told
        // when the down moves - a write-up that moves nothing, like a timeout's, is no play.
        #expect(
            try await live(120, play: "Incomplete", down: "2nd & 10 at KC 41").only?.type
                == HouseEvents.gamePlay)
        #expect(try await live(150, play: "Pass for 12 yards", down: "2nd & 10 at KC 41").isEmpty)
        #expect(
            try await live(155, play: "Pass for 12 yards", down: "1st & 10 at KC 53").only?.type
                == HouseEvents.gameFirstDown)

        // A flag, as ESPN wrote one up on 11-02, with its automatic first down: the flag is
        // the news. ESPN's short name matches neither side here, so it is told as written.
        let roughing =
            " (Shotgun) S.Darnold pass incomplete short left.\nPENALTY on CHI-J.Lynch, Roughing the Passer, 15 yards, enforced at SEA 24 - No Play."
        let flag = try #require(
            try await live(180, play: roughing, down: "1st & 10 at KC 53").only)
        #expect(flag.type == HouseEvents.gamePenalty)
        #expect(flag.payload["penalty_on"] == .string("CHI"))
        #expect(flag.payload["foul"] == .string("Roughing the Passer"))
        #expect(flag.payload["yards"] == .number(15))
        // Its automatic first down, arriving a look later, is still the flag's.
        #expect(try await live(185, play: roughing, down: "1st & 10 at SEA 39").isEmpty)
        // On a side ESPN names by its short name: told by the side's name.
        let offside = try #require(
            try await live(
                210,
                play:
                    "PENALTY on SEA-B.Mafe, Defensive Offside, 5 yards, enforced at SEA 39 - No Play.",
                down: "1st & 5 at SEA 34"
            ).only)
        #expect(offside.payload["penalty_on"] == .string("Seattle Seahawks"))
        // A declined flag leaves just the play; offsetting ones, moving no down, nothing.
        #expect(
            try await live(
                240,
                play: "Run for 3 yards. PENALTY on KC-T.Smith, Offensive Holding, declined.",
                down: "2nd & 2 at SEA 31"
            ).only?.type == HouseEvents.gamePlay)
        #expect(
            try await live(
                270,
                play:
                    "PENALTY on KC-T.Smith, Face Mask, 15 yards. PENALTY on SEA-B.Mafe, Unnecessary Roughness, 15 yards. Penalties offset - No Play.",
                down: "2nd & 2 at SEA 31"
            ).isEmpty)

        // A review's ruling, which ESPN writes up once it is decided: a coach's challenge,
        // then the booth's.
        let challenge = try #require(
            try await live(
                300,
                play:
                    "SEATTLE challenged the pass completion ruling, and the play was REVERSED. (Shotgun) P.Mahomes pass incomplete short right.",
                down: "3rd & 2 at SEA 31"
            ).only)
        #expect(challenge.type == HouseEvents.gameReviewed)
        #expect(challenge.payload["challenged_by"] == .string("SEATTLE"))
        #expect(challenge.payload["outcome"] == .string("reversed"))
        let booth = try #require(
            try await live(
                330,
                play:
                    "I.Pacheco up the middle to SEA 29 for 2 yards. The Replay Official reviewed the runner was down by contact ruling, and the play was Upheld. The ruling on the field stands.",
                down: "1st & 10 at SEA 29"
            ).only)
        #expect(booth.type == HouseEvents.gameReviewed)
        #expect(booth.payload["challenged_by"] == nil)
        #expect(booth.payload["outcome"] == .string("upheld"))
    }

    private func sensor(
        _ state: String, at offset: TimeInterval, changed: TimeInterval? = nil,
        _ attributes: [String: WorldJSONValue] = [:]
    ) -> EntityState {
        var all: [String: WorldJSONValue] = [
            "date": .string(kickoff), "league": .string("NFL"), "team_abbr": .string("SEA"),
            "team_name": .string("Seahawks"), "team_long_name": .string("Seattle Seahawks"),
            "opponent_name": .string("Chiefs"),
            "opponent_long_name": .string("Kansas City Chiefs"),
            "team_homeaway": .string("home"), "team_record": .string("5-2"),
            "team_winner": .null, "opponent_winner": .null,
            "team_id": .string("26"), "opponent_id": .string("12"),
        ]
        all.merge(attributes) { $1 }
        return EntityState(
            entityID: "sensor.seattle_seahawks", state: state, attributes: all,
            lastChanged: kickedOff.addingTimeInterval(changed ?? offset),
            contextID: "ctx-\(state)-\(offset)",
            lastUpdated: kickedOff.addingTimeInterval(offset))
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? self[0] : nil }
}
