import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = TestDatabase.uri

/// The game as April sees it (#288): on 2026-11-08 the birds remarked on plays about 15 s
/// before YouTube TV showed them. A bird keeps how far behind the TV is, and each game event
/// waits that long before the World takes it in.
@Suite("A broadcast delay for the game")
struct BroadcastDelayTests {
    private let now = Date(timeIntervalSince1970: 1_794_180_000)
    private let team = try! EntityID(validating: "team:seahawks")

    @Test("A delay is seconds, said as a number or words starting with one, and never absurd")
    func seconds() throws {
        func delay(_ value: WorldJSONValue) throws -> TimeInterval? {
            BroadcastDelay.seconds(
                in: try Fact(
                    subjectID: EntityID(validating: "house:aprils-nest"),
                    predicate: WorldFacts.gamesDelay, value: value,
                    epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
                    derivedFrom: [], producer: FactProducer(kind: "mind", id: "beaky", version: "1")
                )
            )
        }
        #expect(try delay(.number(15)) == 15)
        #expect(try delay(.string("15")) == 15)
        #expect(try delay(.string("15 seconds")) == 15)
        #expect(try delay(.string(" 12.5 s")) == 12.5)
        // Ended, nonsense, or nothing at all: no delay.
        #expect(try delay(.null) == nil)
        #expect(try delay(.string("none")) == nil)
        #expect(try delay(.number(0)) == nil)
        #expect(BroadcastDelay.seconds(in: nil) == nil)
        // "15 minutes" misheard as 900 s still holds no longer than a TV stream could lag.
        #expect(try delay(.number(900)) == BroadcastDelay.maximumSeconds)
    }

    @Test("A hold fires as the event it held, ESPN's time intact, marked with how long it waited")
    func holdAndRelease() throws {
        let event = try score(at: now)
        let timer = try BroadcastDelay.timer(
            holding: event, for: 15, now: now.addingTimeInterval(1))
        #expect(timer.purpose == BroadcastDelay.purpose)
        #expect(timer.dueAt == now.addingTimeInterval(16))
        // Named by the event: sent again while it waits, it is held once.
        #expect(
            try BroadcastDelay.timer(holding: event, for: 15, now: now.addingTimeInterval(3))
                .timerID
                == timer.timerID)

        let released = try WorldTimerScheduler.firedEvent(
            for: timer, firingAt: now.addingTimeInterval(16))
        #expect(released.eventID == event.eventID)
        #expect(released.type == HouseEvents.gameScored)
        #expect(released.source == event.source)
        #expect(released.occurredAt == event.occurredAt)
        #expect(released.payload["team_score"] == .number(7))
        #expect(released.payload["held_seconds"] == .number(15))
    }

    @Test("A held event is still news when it is released, and stale news is still stale")
    func newsAfterAHold() throws {
        var released = try score(at: now)
        released.receivedAt = now.addingTimeInterval(61)
        #expect(SceneOpeningPolicy.isNews(released, within: 45) == false)
        released.payload["held_seconds"] = .number(60)
        #expect(SceneOpeningPolicy.isNews(released, within: 45))
        released.receivedAt = now.addingTimeInterval(200)
        #expect(SceneOpeningPolicy.isNews(released, within: 45) == false)
    }

    func score(at moment: Date) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: HouseEvents.gameScored, occurredAt: moment,
            source: EventSource(
                id: SourceID(validating: "home-assistant:sensor-seattle-seahawks"),
                kind: "home-assistant", sourceEventID: "context:\(UUID().uuidString)"),
            subjectIDs: [team], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [
                "kickoff": .string(WorldJSON.timestamp(moment.addingTimeInterval(-600))),
                "team": .string("Seattle Seahawks"), "opponent": .string("Arizona Cardinals"),
                "team_score": .number(7), "opponent_score": .number(0),
                "scored_by": .string("Seattle Seahawks"), "clock": .string("9:12 - 1st"),
            ])
    }
}

@Suite(
    "A broadcast delay at the World's door, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct BroadcastDelayMongoTests {
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    @Test("With a delay kept, a score waits: the game's facts move only when it is released")
    func scoreWaitsForTheTV() async throws {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "broadcast-delay-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [GivenFactReducer(), GameReducer(zone: TimeZone(identifier: "UTC")!)],
            clock: ManualWorldClock(now: now))
        let house = try EntityID(validating: "house:delay-\(UUID().uuidString.lowercased())")
        let team = try EntityID(validating: "team:delay-\(UUID().uuidString.lowercased())")
        var held: [WorldTimer] = []
        func door(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance? {
            try await BroadcastDelay.hold(
                event, house: house, facts: persistence.facts, events: persistence.events,
                now: now, schedule: { held.append($0) })
        }
        func playing() async throws -> Fact? {
            try await persistence.facts.fact(of: team, WorldFacts.gamePlaying, at: now + 60)
        }
        var score = try BroadcastDelayTests().score(at: now)
        score.subjectIDs = [team]

        // No delay kept: straight in.
        #expect(try await door(score) == nil)

        // Beaky keeps "YouTube TV is 15 seconds behind", for today.
        _ = try await world.accept(
            try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType, occurredAt: now - 5,
                source: EventSource(
                    id: SourceID(validating: "mind:beaky"), kind: "mind",
                    sourceEventID: UUID().uuidString),
                subjectIDs: [house], epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: [
                    "subject_id": .string(house.rawValue),
                    "predicate": .string(WorldFacts.gamesDelay), "value": .string("15"),
                    "valid_for_seconds": .number(3_600),
                ]))
        let acceptance = try #require(try await door(score))
        #expect(acceptance.disposition == .held)
        #expect(held.count == 1)
        #expect(try await playing() == nil)

        // Not a game's: never held.
        var doorbell = score
        doorbell.eventID = .generated()
        doorbell.type = HouseEvents.doorOpened
        #expect(try await door(doorbell) == nil)

        // The hold fires: the score goes in as the house sent it, and the game's facts move.
        let released = try WorldTimerScheduler.firedEvent(
            for: try #require(held.first), firingAt: now + 15)
        #expect(try await world.accept(released).disposition == .accepted)
        let fact = try #require(try await playing())
        guard case .object(let game) = fact.value else {
            Issue.record("not a game: \(fact.value)")
            return
        }
        #expect(game["team_score"] == .number(7))
        #expect(fact.validFrom == now)

        // The house sending it again after: the World has it, so it is not held twice.
        #expect(try await door(score) == nil)
    }
}
