import Foundation
import MongoKitten
import Testing
import WorldCore

@testable import creature_world

/// The Seahawks' home win over the Chiefs on 2026-10-25, kicked off at 5:20 PM Pacific, and the
/// Bears a week later, after the clocks went back (#269).
private let chiefsKickoff = "2026-10-26T00:20:00.000Z"
private let bearsKickoff = "2026-11-03T01:15:00.000Z"
private let whistle = "2026-10-26T03:31:12.000Z"
private let pacific = TimeZone(identifier: "America/Los_Angeles")!

private func gameEvent(
    _ type: WorldEventType, _ team: EntityID, kickoff: String = chiefsKickoff,
    source: String = "home-assistant:sensor-seattle-seahawks", key: String,
    _ extra: [String: WorldJSONValue] = [:]
) throws -> WorldEventEnvelope {
    var payload: [String: WorldJSONValue] = [
        "kickoff": .string(kickoff), "team": .string("Seattle Seahawks"),
        "opponent": .string(kickoff == chiefsKickoff ? "Kansas City Chiefs" : "Chicago Bears"),
        "home_away": .string("home"),
    ]
    payload.merge(extra) { $1 }
    // A final happens at its whistle, when there is one; the rest at kickoff.
    var at = kickoff
    if case .string(let ended)? = extra["ended_at"] { at = ended }
    return try WorldEventEnvelope(
        type: type, occurredAt: WorldJSON.date(from: at)!,
        source: EventSource(
            id: try SourceID(validating: source), kind: HouseEvents.sourceKind,
            sourceEventID: key),
        subjectIDs: [team], epistemic: EpistemicState(type: .observed, confidence: 1),
        payload: payload)
}

private let finalScore: [String: WorldJSONValue] = [
    "team_score": .number(20), "opponent_score": .number(3), "result": .string("won"),
]

@Suite("A team's games, as facts")
struct GameReducerTests {
    private let team = try! EntityID(validating: "team:seahawks")
    private let reducer = GameReducer(zone: pacific)

    @Test("Published is the next game, with its kickoff in words where the house is")
    func scheduled() throws {
        let reduction = try reducer.reduce(
            try gameEvent(
                HouseEvents.gameScheduled, team, kickoff: bearsKickoff, key: "game:b:scheduled"))
        let next = try #require(reduction.changedFacts.only)
        #expect(next.subjectID == team)
        #expect(next.predicate == WorldFacts.gameNext)
        #expect(next.validTo == nil)
        #expect(next.epistemic.type == .observed)
        guard case .object(let game) = next.value else {
            Issue.record("not a game: \(next.value)")
            return
        }
        // After the clocks went back: PST.
        #expect(game["when"] == .string("Monday, November 2 at 5:15 PM"))
        #expect(game["kickoff"] == .string(bearsKickoff))
        #expect(game["opponent"] == .string("Chicago Bears"))
        #expect(game["home_away"] == .string("home"))
        #expect(game["team"] == .string("Seattle Seahawks"))
        #expect(reduction.retractions.isEmpty)
    }

    @Test("Under way, it is playing and no longer next")
    func started() throws {
        let reduction = try reducer.reduce(
            try gameEvent(HouseEvents.gameStarted, team, key: "game:c:started"))
        let playing = try #require(reduction.changedFacts.only)
        #expect(playing.predicate == WorldFacts.gamePlaying)
        guard case .object(let game) = playing.value else {
            Issue.record("not a game: \(playing.value)")
            return
        }
        #expect(game["when"] == .string("Sunday, October 25 at 5:20 PM"))
        #expect(game["team_score"] == nil)
        let ends = try #require(reduction.retractions.only)
        #expect(ends.predicatePrefix == WorldFacts.gameNext)
        #expect(ends.bases == [.observed])
    }

    @Test("Final, it is the last game - the score, the result, the whistle - and nothing else")
    func final() throws {
        var whistled = finalScore
        whistled["ended_at"] = .string(whistle)
        let reduction = try reducer.reduce(
            try gameEvent(HouseEvents.gameFinal, team, key: "game:c:final", whistled))
        let last = try #require(reduction.changedFacts.only)
        #expect(last.predicate == WorldFacts.gameLast)
        guard case .object(let game) = last.value else {
            Issue.record("not a game: \(last.value)")
            return
        }
        #expect(game["team_score"] == .number(20))
        #expect(game["opponent_score"] == .number(3))
        #expect(game["result"] == .string("won"))
        #expect(game["ended_at"] == .string(whistle))
        #expect(game["ended"] == .string("Sunday, October 25 at 8:31 PM"))
        let ends = try #require(reduction.retractions.only)
        #expect(ends.predicatePrefix == "game.")
        #expect(ends.except == [WorldFacts.gameLast])

        // Seen only at startup: no whistle, and no words for one.
        let snapshot = try reducer.reduce(
            try gameEvent(HouseEvents.gameFinal, team, key: "game:c:final", finalScore))
        guard case .object(let unwhistled)? = snapshot.changedFacts.only?.value else {
            Issue.record("no game")
            return
        }
        #expect(unwhistled["ended"] == nil)
        #expect(unwhistled["ended_at"] == nil)
    }

    @Test("A score keeps the game under way, with the score and the clock then")
    func scored() throws {
        for type in [HouseEvents.gameScored, HouseEvents.gameScoreCorrected] {
            let reduction = try reducer.reduce(
                try gameEvent(
                    type, team, key: "context:x",
                    [
                        "team_score": .number(7), "opponent_score": .number(3),
                        "clock": .string("7:12 - 2nd"), "scored_by": .string("Seattle Seahawks"),
                        "last_play": .string("J. Smith 12 Yd Run (K. Jones Kick)"),
                    ]))
            let playing = try #require(reduction.changedFacts.only)
            #expect(playing.predicate == WorldFacts.gamePlaying)
            guard case .object(let game) = playing.value else {
                Issue.record("not a game: \(playing.value)")
                return
            }
            #expect(game["team_score"] == .number(7))
            #expect(game["opponent_score"] == .number(3))
            #expect(game["clock"] == .string("7:12 - 2nd"))
            // Who scored and the play are the moment's, for the scene; the fact is the score.
            #expect(game["scored_by"] == nil)
            #expect(game["last_play"] == nil)
            #expect(reduction.retractions.only?.predicatePrefix == WorldFacts.gameNext)
        }
    }

    @Test("The ball changing hands keeps the game under way, with who has it and where")
    func possession() throws {
        let reduction = try reducer.reduce(
            try gameEvent(
                HouseEvents.gamePossession, team, key: "context:y",
                [
                    "team_score": .number(0), "opponent_score": .number(7),
                    "clock": .string("2:40 - 1st"), "possession": .string("Seattle Seahawks"),
                    "down_distance": .string("1st & 10 at SEA 25"),
                    "last_play": .string("C. Santos kicks 65 yards, touchback."),
                ]))
        let playing = try #require(reduction.changedFacts.only)
        #expect(playing.predicate == WorldFacts.gamePlaying)
        guard case .object(let game) = playing.value else {
            Issue.record("not a game: \(playing.value)")
            return
        }
        #expect(game["possession"] == .string("Seattle Seahawks"))
        #expect(game["down_distance"] == .string("1st & 10 at SEA 25"))
        #expect(game["opponent_score"] == .number(7))
        #expect(game["last_play"] == nil)
    }

    @Test("A game with no kickoff is no game")
    func noKickoff() throws {
        var event = try gameEvent(HouseEvents.gameFinal, team, key: "game:x:final", finalScore)
        event.payload["kickoff"] = nil
        let reduction = try reducer.reduce(event)
        #expect(reduction.changedFacts.isEmpty)
        #expect(reduction.retractions.isEmpty)
    }

    @Test("Each game kind means something to a mind")
    func glossary() {
        for predicate in [WorldFacts.gameNext, WorldFacts.gamePlaying, WorldFacts.gameLast] {
            #expect(WorldFacts.meanings[predicate]?.isEmpty == false)
        }
    }
}

@Suite(
    "A team's games, in a real World",
    .enabled(if: TestDatabase.uri != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct GameWorldTests {
    @Test(
        "A live final keeps its whistle when a restart tells the same final again, and is found by name"
    )
    func liveFinalKeepsItsWhistle() async throws {
        let uri = try #require(TestDatabase.uri)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "game-world-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        // Run-unique, so other runs' games in the shared database never answer.
        let run = runUniqueWord()
        let team = try EntityID(validating: "team:seahawks-\(run)")
        let source = "home-assistant:sensor-\(run)"
        let clock = ManualWorldClock(now: Date(timeIntervalSince1970: 1_793_000_000))
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [GameReducer(zone: pacific)], clock: clock)

        _ = try await world.accept(
            try gameEvent(
                HouseEvents.gameScheduled, team, source: source,
                key: "game:\(chiefsKickoff):scheduled"))
        _ = try await world.accept(
            try gameEvent(
                HouseEvents.gameStarted, team, source: source,
                key: "game:\(chiefsKickoff):started"))
        var whistled = finalScore
        whistled["ended_at"] = .string(whistle)
        let live = try await world.accept(
            try gameEvent(
                HouseEvents.gameFinal, team, source: source, key: "game:\(chiefsKickoff):final",
                whistled))
        #expect(live.disposition == .accepted)

        // creature-house restarts the next day and its snapshot tells the same final, with no
        // whistle: the same game, the same key, and nothing changes.
        try await clock.advance(by: 86_400)
        let again = try await world.accept(
            try gameEvent(
                HouseEvents.gameFinal, team, source: source, key: "game:\(chiefsKickoff):final",
                finalScore))
        #expect(again.disposition == .duplicateSourceEvent)

        let current = try await persistence.facts.currentFacts(
            subjectID: team, at: await clock.now)
        let byPredicate = Dictionary(uniqueKeysWithValues: current.map { ($0.predicate, $0) })
        #expect(byPredicate[WorldFacts.gameNext] == nil)
        #expect(byPredicate[WorldFacts.gamePlaying] == nil)
        let last = try #require(byPredicate[WorldFacts.gameLast])
        guard case .object(let game) = last.value else {
            Issue.record("not a game: \(last.value)")
            return
        }
        #expect(game["ended"] == .string("Sunday, October 25 at 8:31 PM"))
        #expect(game["result"] == .string("won"))

        // What a bird's search_world does with "Seahawks": the team, by its id and its name.
        let found = try await persistence.facts.search(
            "seahawks \(run)", limit: 10, at: await clock.now)
        #expect(found.contains { $0.0.subjectID == team && $0.0.predicate == WorldFacts.gameLast })
    }

    @Test("The games ride on no bird's page, named or not: a bird looks them up (#269)")
    func lookedUpNeverHanded() async throws {
        let uri = try #require(TestDatabase.uri)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "game-world-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let run = runUniqueWord()
        let team = try EntityID(validating: "team:seahawks-\(run)")
        let beaky = try EntityID(validating: "character:beaky-\(run)")
        let region = try EntityID(validating: "region:\(run)")
        let clock = ManualWorldClock(now: Date(timeIntervalSince1970: 1_793_000_000))
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [GameReducer(zone: pacific)], clock: clock)
        var whistled = finalScore
        whistled["ended_at"] = .string(whistle)
        _ = try await world.accept(
            try gameEvent(
                HouseEvents.gameFinal, team, source: "home-assistant:sensor-\(run)",
                key: "game:\(chiefsKickoff):final", whistled))
        let sessions = CharacterSessionService(
            repository: persistence.characterSessions, clock: clock, announce: { _ in })
        _ = try await sessions.login(
            beaky,
            CharacterLoginRequest(
                regionID: region, instance: CharacterMindInstance(host: "test", processID: 1)))
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: sessions, regions: [region: RegionConfiguration(stageID: "s", places: [])],
            clock: clock)

        // April: "I don't want to put the sports info in the message envelope."
        let asked = try await knowledge.page(
            about: [beaky], mentionedIn: "Did the Seahawks \(run) win last night?", limit: 30)
        #expect(!asked.facts.contains { $0.predicate.hasPrefix("game.") })
        // The team asked for by id - a look-up - is where they are.
        let lookedUp = try await knowledge.page(about: [beaky, team], mentionedIn: nil, limit: 30)
        #expect(lookedUp.facts.contains { $0.predicate == WorldFacts.gameLast })
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? self[0] : nil }
}
