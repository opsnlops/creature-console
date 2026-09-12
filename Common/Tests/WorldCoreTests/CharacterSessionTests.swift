import Foundation
import Testing
import WorldCore

@Suite("Character sessions")
struct CharacterSessionTests {
    private static let now = Date(timeIntervalSince1970: 1_789_300_000)
    private let beaky = try! EntityID(validating: "character:beaky")
    private let home = try! EntityID(validating: "region:home")
    private let aviary = try! EntityID(validating: "region:aviary")
    private let fuzzball = CharacterMindInstance(host: "fuzzball", processID: 100, creatureID: "u1")
    private let laptop = CharacterMindInstance(host: "laptop", processID: 200, creatureID: "u1")

    @Test("The first mind to log in holds the character; a second is told to spectate")
    func secondMindSpectates() async throws {
        let (service, announced, _) = makeService()

        let first = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: fuzzball))
        let second = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: laptop))

        #expect(first.disposition == .loggedIn)
        #expect(second.disposition == .loggedInElsewhere)
        #expect(second.session == first.session)
        #expect(await announced.types == [CharacterSessionService.loginEventType])
        #expect(try await service.present(in: home).map(\.sessionID) == [first.session.sessionID])
    }

    @Test("Heartbeats keep a session alive; without them it expires and another mind may log in")
    func heartbeatsAndExpiry() async throws {
        let (service, announced, clock) = makeService(lifetime: 30)
        let first = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: fuzzball))

        try await clock.advance(by: 20)
        let beat = try await service.heartbeat(
            beaky, CharacterSessionReference(sessionID: first.session.sessionID))
        #expect(beat.expiresAt == Self.now.addingTimeInterval(50))

        try await clock.advance(by: 31)
        #expect(try await service.liveSession(for: beaky) == nil)
        #expect(try await service.characterSessions().first?.state == .expired)
        await #expect(throws: WorldContractError.characterSessionNotLive) {
            try await service.heartbeat(
                beaky, CharacterSessionReference(sessionID: first.session.sessionID))
        }

        let takeover = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: laptop))
        #expect(takeover.disposition == .loggedIn)
        #expect(takeover.session.instance == laptop)
        #expect(await announced.types.count == 2)
    }

    @Test("The same mind logging in again renews; logging into another region moves it")
    func renewalAndRegionMove() async throws {
        let (service, _, clock) = makeService()
        let first = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: fuzzball))
        try await clock.advance(by: 5)

        let renewed = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: fuzzball))
        #expect(renewed.disposition == .renewed)
        #expect(renewed.session.sessionID == first.session.sessionID)

        let moved = try await service.login(
            beaky, CharacterLoginRequest(regionID: aviary, instance: fuzzball))
        #expect(moved.disposition == .loggedIn)
        #expect(moved.session.sessionID != first.session.sessionID)
        #expect(try await service.present(in: home).isEmpty)
        #expect(try await service.present(in: aviary).count == 1)
    }

    @Test("Logout ends the session, announces it, and frees the character")
    func logoutFreesTheCharacter() async throws {
        let (service, announced, _) = makeService()
        let first = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: fuzzball))

        let ended = try await service.logout(
            beaky, CharacterSessionReference(sessionID: first.session.sessionID))
        let next = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: laptop))

        #expect(ended.state == .loggedOut)
        #expect(next.disposition == .loggedIn)
        #expect(
            await announced.types == [
                CharacterSessionService.loginEventType, CharacterSessionService.logoutEventType,
                CharacterSessionService.loginEventType,
            ])
    }

    @Test(
        "Only the live session's holder may act as the character; nobody logged in means anyone may"
    )
    func holderCheck() async throws {
        let (service, _, _) = makeService()
        try await service.requireHolder(of: beaky, sessionID: nil)

        let first = try await service.login(
            beaky, CharacterLoginRequest(regionID: home, instance: fuzzball))

        try await service.requireHolder(of: beaky, sessionID: first.session.sessionID)
        await #expect(throws: WorldContractError.characterSessionNotLive) {
            try await service.requireHolder(of: beaky, sessionID: nil)
        }
        await #expect(throws: WorldContractError.characterSessionNotLive) {
            try await service.requireHolder(of: beaky, sessionID: .generated())
        }
    }

    @Test("Sessions round-trip through the snake_case wire contract")
    func wireContract() throws {
        let session = try CharacterSession(
            characterID: beaky, regionID: home, instance: fuzzball,
            loggedInAt: Self.now, lastHeartbeatAt: Self.now,
            expiresAt: Self.now.addingTimeInterval(30))
        let data = try WorldJSON.makeEncoder().encode(session)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(
            Set(json.keys) == [
                "schema_version", "session_id", "character_id", "region_id", "instance", "state",
                "logged_in_at", "last_heartbeat_at", "expires_at",
            ])
        #expect((json["instance"] as? [String: Any])?["process_id"] as? Int == 100)
        #expect(try WorldJSON.makeDecoder().decode(CharacterSession.self, from: data) == session)
    }

    private func makeService(lifetime: TimeInterval = 30) -> (
        CharacterSessionService, AnnouncedEvents, ManualWorldClock
    ) {
        let clock = ManualWorldClock(now: Self.now)
        let announced = AnnouncedEvents()
        let service = CharacterSessionService(
            repository: InMemorySessionRepository(),
            clock: clock,
            sessionLifetime: lifetime,
            announce: { await announced.record($0) }
        )
        return (service, announced, clock)
    }
}

private actor InMemorySessionRepository: CharacterSessionRepository {
    private var sessions: [CharacterSessionID: CharacterSession] = [:]

    func session(for characterID: EntityID) -> CharacterSession? {
        sessions.values.filter { $0.characterID == characterID }
            .max { ($0.loggedInAt, $0.sessionID.rawValue) < ($1.loggedInAt, $1.sessionID.rawValue) }
    }

    func session(id: CharacterSessionID) -> CharacterSession? { sessions[id] }

    func save(_ session: CharacterSession) { sessions[session.sessionID] = session }

    func latestSessions() -> [CharacterSession] {
        Dictionary(grouping: sessions.values, by: \.characterID).values.compactMap {
            $0.max { $0.loggedInAt < $1.loggedInAt }
        }
    }
}

private actor AnnouncedEvents {
    private(set) var types: [WorldEventType] = []
    func record(_ event: WorldEventEnvelope) { types.append(event.type) }
}
