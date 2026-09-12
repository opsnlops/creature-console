import Foundation
import Tracing

/// Where a mind says it is running from, so a second copy of the same character can be told
/// apart from a heartbeat of the first.
public struct CharacterMindInstance: Hashable, Sendable, Codable {
    public var host: String
    public var processID: Int
    public var creatureID: String?
    public var version: String?
    /// The character's pronouns, from its persona: the mind tells the world at login so the
    /// others can be told ("Mango (he/him) is here").
    public var pronouns: String?

    public init(
        host: String, processID: Int, creatureID: String? = nil, version: String? = nil,
        pronouns: String? = nil
    ) {
        self.host = host
        self.processID = processID
        self.creatureID = creatureID
        self.version = version
        self.pronouns = pronouns
    }

    private enum CodingKeys: String, CodingKey {
        case host
        case processID = "process_id"
        case creatureID = "creature_id"
        case version
        case pronouns
    }
}

/// A mind asking to be a character in a region.
public struct CharacterLoginRequest: Hashable, Sendable, Codable {
    public var regionID: EntityID
    public var instance: CharacterMindInstance

    public init(regionID: EntityID, instance: CharacterMindInstance) {
        self.regionID = regionID
        self.instance = instance
    }

    private enum CodingKeys: String, CodingKey {
        case regionID = "region_id"
        case instance
    }
}

public enum CharacterSessionState: String, Hashable, Sendable, Codable {
    case active
    case loggedOut = "logged_out"
    case expired
}

/// A character's presence in the world: one mind, one region, kept alive by heartbeats.
///
/// This is the first character presence the world has. "Who is in the room" for a scene is
/// "whose session is active in this region". A character is in one region at a time; logging
/// in elsewhere ends the earlier session.
public struct CharacterSession: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var sessionID: CharacterSessionID
    public var characterID: EntityID
    public var regionID: EntityID
    public var instance: CharacterMindInstance
    public var state: CharacterSessionState
    public var loggedInAt: Date
    public var lastHeartbeatAt: Date
    public var expiresAt: Date
    public var endedAt: Date?

    public init(
        sessionID: CharacterSessionID = .generated(),
        characterID: EntityID,
        regionID: EntityID,
        instance: CharacterMindInstance,
        state: CharacterSessionState = .active,
        loggedInAt: Date,
        lastHeartbeatAt: Date,
        expiresAt: Date,
        endedAt: Date? = nil
    ) throws {
        guard expiresAt >= lastHeartbeatAt, lastHeartbeatAt >= loggedInAt else {
            throw WorldContractError.invalidDateInterval
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.sessionID = sessionID
        self.characterID = characterID
        self.regionID = regionID
        self.instance = instance
        self.state = state
        self.loggedInAt = loggedInAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.expiresAt = expiresAt
        self.endedAt = endedAt
    }

    /// Active and not yet expired at `now`.
    public func isLive(at now: Date) -> Bool {
        state == .active && expiresAt > now
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            sessionID: container.decode(CharacterSessionID.self, forKey: .sessionID),
            characterID: container.decode(EntityID.self, forKey: .characterID),
            regionID: container.decode(EntityID.self, forKey: .regionID),
            instance: container.decode(CharacterMindInstance.self, forKey: .instance),
            state: container.decode(CharacterSessionState.self, forKey: .state),
            loggedInAt: container.decode(Date.self, forKey: .loggedInAt),
            lastHeartbeatAt: container.decode(Date.self, forKey: .lastHeartbeatAt),
            expiresAt: container.decode(Date.self, forKey: .expiresAt),
            endedAt: container.decodeIfPresent(Date.self, forKey: .endedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case characterID = "character_id"
        case regionID = "region_id"
        case instance
        case state
        case loggedInAt = "logged_in_at"
        case lastHeartbeatAt = "last_heartbeat_at"
        case expiresAt = "expires_at"
        case endedAt = "ended_at"
    }
}

public enum CharacterLoginDisposition: String, Hashable, Sendable, Codable {
    /// A new session was opened for this mind.
    case loggedIn = "logged_in"
    /// This mind already held the character; its session was renewed.
    case renewed
    /// Another mind holds the character right now; this one must spectate.
    case loggedInElsewhere = "logged_in_elsewhere"
}

public struct CharacterLoginResult: Hashable, Sendable, Codable {
    public var disposition: CharacterLoginDisposition
    /// The session this mind holds, or — when logged in elsewhere — the session that holds it.
    public var session: CharacterSession

    public init(disposition: CharacterLoginDisposition, session: CharacterSession) {
        self.disposition = disposition
        self.session = session
    }
}

public struct CharacterSessionReference: Hashable, Sendable, Codable {
    public var sessionID: CharacterSessionID

    public init(sessionID: CharacterSessionID) {
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

public struct CharacterSessionPage: Hashable, Sendable, Codable {
    public var sessions: [CharacterSession]

    public init(sessions: [CharacterSession]) {
        self.sessions = sessions
    }
}

public protocol CharacterSessionRepository: Sendable {
    /// The most recent session for a character, whatever its state.
    func session(for characterID: EntityID) async throws -> CharacterSession?
    func session(id: CharacterSessionID) async throws -> CharacterSession?
    func save(_ session: CharacterSession) async throws
    /// Every character's most recent session, newest login first.
    func latestSessions() async throws -> [CharacterSession]
}

/// Character login as a world rule: one mind per character, one region per character, and a
/// heartbeat that keeps it so. Nothing here decides what a character says; it only decides
/// which process is allowed to be them.
public actor CharacterSessionService {
    public static let loginEventType = WorldEventType(rawValue: "character.logged_in")!
    public static let logoutEventType = WorldEventType(rawValue: "character.logged_out")!
    public static let sourceID = try! SourceID(validating: "world:character-sessions")

    private let repository: any CharacterSessionRepository
    private let clock: any WorldClock
    private let sessionLifetime: TimeInterval
    private let announce: @Sendable (WorldEventEnvelope) async throws -> Void

    public init(
        repository: any CharacterSessionRepository,
        clock: any WorldClock,
        sessionLifetime: TimeInterval = 30,
        announce: @escaping @Sendable (WorldEventEnvelope) async throws -> Void
    ) {
        precondition(sessionLifetime > 0)
        self.repository = repository
        self.clock = clock
        self.sessionLifetime = sessionLifetime
        self.announce = announce
    }

    public func login(
        _ characterID: EntityID,
        _ request: CharacterLoginRequest
    ) async throws -> CharacterLoginResult {
        try await withSpan("character.session.login") { span in
            span.attributes["agent.character_id"] = characterID.rawValue
            span.attributes["world.region_id"] = request.regionID.rawValue
            let now = await clock.now
            if let current = try await repository.session(for: characterID), current.isLive(at: now)
            {
                if current.instance == request.instance {
                    var renewed = current
                    renewed.lastHeartbeatAt = now
                    renewed.expiresAt = now.addingTimeInterval(sessionLifetime)
                    if renewed.regionID != request.regionID {
                        // Same mind, new region: the earlier session ends and a new one opens.
                        return try await open(characterID, request, now: now, ending: current)
                    }
                    try await repository.save(renewed)
                    span.attributes["character.session.disposition"] =
                        CharacterLoginDisposition.renewed.rawValue
                    return CharacterLoginResult(disposition: .renewed, session: renewed)
                }
                span.attributes["character.session.disposition"] =
                    CharacterLoginDisposition.loggedInElsewhere.rawValue
                return CharacterLoginResult(disposition: .loggedInElsewhere, session: current)
            }
            return try await open(characterID, request, now: now, ending: nil)
        }
    }

    public func heartbeat(
        _ characterID: EntityID,
        _ reference: CharacterSessionReference
    ) async throws -> CharacterSession {
        let now = await clock.now
        guard var session = try await repository.session(id: reference.sessionID),
            session.characterID == characterID, session.isLive(at: now)
        else { throw WorldContractError.characterSessionNotLive }
        session.lastHeartbeatAt = now
        session.expiresAt = now.addingTimeInterval(sessionLifetime)
        try await repository.save(session)
        return session
    }

    public func logout(
        _ characterID: EntityID,
        _ reference: CharacterSessionReference
    ) async throws -> CharacterSession {
        let now = await clock.now
        guard var session = try await repository.session(id: reference.sessionID),
            session.characterID == characterID
        else { throw WorldContractError.characterSessionNotLive }
        guard session.state == .active else { return session }
        session.state = .loggedOut
        session.endedAt = now
        try await repository.save(session)
        try await announce(makeEvent(Self.logoutEventType, session: session, at: now))
        return session
    }

    /// The live session a mind must hold to act as this character, if any.
    public func liveSession(for characterID: EntityID) async throws -> CharacterSession? {
        let now = await clock.now
        guard let session = try await repository.session(for: characterID), session.isLive(at: now)
        else { return nil }
        return session
    }

    /// Characters logged into a region right now.
    public func present(in regionID: EntityID) async throws -> [CharacterSession] {
        let now = await clock.now
        return try await repository.latestSessions().filter {
            $0.regionID == regionID && $0.isLive(at: now)
        }
    }

    /// Marks sessions whose heartbeat stopped as expired and announces their logout, so the
    /// world's facts about who is present do not outlive the mind. Meant to run periodically.
    public func sweepExpired() async throws {
        let now = await clock.now
        for session in try await repository.latestSessions()
        where session.state == .active && session.expiresAt <= now {
            var expired = session
            expired.state = .expired
            expired.endedAt = session.expiresAt
            try await repository.save(expired)
            try await announce(makeEvent(Self.logoutEventType, session: expired, at: now))
        }
    }

    /// Every character's most recent session, with lapsed ones reported as expired.
    public func characterSessions() async throws -> [CharacterSession] {
        let now = await clock.now
        return try await repository.latestSessions().map { session in
            var session = session
            if session.state == .active, session.expiresAt <= now {
                session.state = .expired
                session.endedAt = session.expiresAt
            }
            return session
        }
    }

    private func open(
        _ characterID: EntityID,
        _ request: CharacterLoginRequest,
        now: Date,
        ending previous: CharacterSession?
    ) async throws -> CharacterLoginResult {
        if var previous {
            previous.state = .loggedOut
            previous.endedAt = now
            try await repository.save(previous)
        }
        let session = try CharacterSession(
            characterID: characterID,
            regionID: request.regionID,
            instance: request.instance,
            loggedInAt: now,
            lastHeartbeatAt: now,
            expiresAt: now.addingTimeInterval(sessionLifetime)
        )
        try await repository.save(session)
        try await announce(makeEvent(Self.loginEventType, session: session, at: now))
        return CharacterLoginResult(disposition: .loggedIn, session: session)
    }

    private func makeEvent(
        _ type: WorldEventType,
        session: CharacterSession,
        at now: Date
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: type,
            occurredAt: now,
            source: EventSource(id: Self.sourceID, kind: "world"),
            subjectIDs: [session.characterID, session.regionID],
            placeID: session.regionID,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: {
                var payload: [String: WorldJSONValue] = [
                    "session_id": .string(session.sessionID.rawValue),
                    "character_id": .string(session.characterID.rawValue),
                    "region_id": .string(session.regionID.rawValue),
                    "host": .string(session.instance.host),
                ]
                if let pronouns = session.instance.pronouns {
                    payload["pronouns"] = .string(pronouns)
                }
                return payload
            }()
        )
    }
}

extension CharacterSessionService {
    /// Refuses a mind that does not hold the character's live session, when one exists. A
    /// character nobody is logged in as may still be spoken for by hand (wizard mode).
    public func requireHolder(
        of characterID: EntityID,
        sessionID: CharacterSessionID?
    ) async throws {
        guard let live = try await liveSession(for: characterID) else { return }
        guard live.sessionID == sessionID else {
            throw WorldContractError.characterSessionNotLive
        }
    }
}
