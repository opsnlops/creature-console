import Foundation
import Logging
import Metrics
import Tracing
import WorldCore

/// The world's login desk, as the mind sees it.
protocol WorldSessionClient: Sendable {
    func login(_ characterID: EntityID, _ request: CharacterLoginRequest) async throws
        -> CharacterLoginResult
    func heartbeat(_ characterID: EntityID, _ reference: CharacterSessionReference) async throws
        -> CharacterSession
    func logout(_ characterID: EntityID, _ reference: CharacterSessionReference) async throws
        -> CharacterSession
}

enum WorldCharacterSessionError: Error, Equatable {
    /// The world says another mind holds this character right now.
    case loggedInElsewhere(host: String)
    /// The world no longer recognises our session (it lapsed, or we were logged out).
    case sessionLost
}

/// Who this mind is in the world: one character, one region, one session kept alive by
/// heartbeats. A mind that cannot get the character spectates — it follows nothing and says
/// nothing — until the world lets it in.
actor WorldCharacterSession {
    private let client: any WorldSessionClient
    private let characterID: EntityID
    private let regionID: EntityID
    private let instance: CharacterMindInstance
    private let heartbeatInterval: Duration
    private let logger: Logger
    private var session: CharacterSession?

    init(
        client: any WorldSessionClient,
        characterID: EntityID,
        regionID: EntityID,
        instance: CharacterMindInstance,
        heartbeatInterval: Duration = .seconds(10),
        logger: Logger
    ) {
        self.client = client
        self.characterID = characterID
        self.regionID = regionID
        self.instance = instance
        self.heartbeatInterval = heartbeatInterval
        self.logger = logger
    }

    /// The session this mind holds, if it currently is the character.
    var sessionID: CharacterSessionID? { session?.sessionID }

    /// Logs in, or throws `loggedInElsewhere` so the caller can wait and try again.
    func login() async throws {
        let result = try await withSpan("agent.session.login", ofKind: .client) { span in
            span.attributes["agent.character_id"] = characterID.rawValue
            span.attributes["world.region_id"] = regionID.rawValue
            let result = try await client.login(
                characterID, CharacterLoginRequest(regionID: regionID, instance: instance))
            span.attributes["character.session.disposition"] = result.disposition.rawValue
            return result
        }
        Counter(
            label: "creature_agent.session.logins",
            dimensions: [("disposition", result.disposition.rawValue)]
        ).increment()
        switch result.disposition {
        case .loggedIn, .renewed:
            session = result.session
            logger.info(
                "Logged into Creature World",
                metadata: [
                    "agent.character_id": "\(characterID.rawValue)",
                    "world.region_id": "\(regionID.rawValue)",
                    "character.session.id": "\(result.session.sessionID.rawValue)",
                ]
            )
        case .loggedInElsewhere:
            session = nil
            logger.warning(
                "Another mind holds this character; spectating",
                metadata: [
                    "agent.character_id": "\(characterID.rawValue)",
                    "character.session.host": "\(result.session.instance.host)",
                    "character.session.expires_at": "\(result.session.expiresAt)",
                ]
            )
            throw WorldCharacterSessionError.loggedInElsewhere(host: result.session.instance.host)
        }
    }

    /// Heartbeats until cancelled, or throws `sessionLost` when the world stops recognising us.
    func keepAlive() async throws {
        while true {
            try await Task.sleep(for: heartbeatInterval)
            guard let current = session else { throw WorldCharacterSessionError.sessionLost }
            do {
                session = try await client.heartbeat(
                    characterID, CharacterSessionReference(sessionID: current.sessionID))
            } catch let error as WorldResponderError {
                // A refusal means the session is gone; anything else is the world being away,
                // which the next heartbeat will find out about.
                if case .rejected = error {
                    session = nil
                    logger.warning("The world no longer recognises this mind's session")
                    throw WorldCharacterSessionError.sessionLost
                }
                logger.warning(
                    "Heartbeat did not reach the world", metadata: ["error": "\(error)"])
            }
        }
    }

    func logout() async {
        guard let current = session else { return }
        session = nil
        do {
            _ = try await client.logout(
                characterID, CharacterSessionReference(sessionID: current.sessionID))
            logger.info(
                "Logged out of Creature World",
                metadata: ["character.session.id": "\(current.sessionID.rawValue)"])
        } catch {
            logger.warning(
                "Could not log out cleanly; the session will lapse",
                metadata: ["error": "\(error)"])
        }
    }
}
