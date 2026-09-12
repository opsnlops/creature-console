import Foundation
import MongoKitten
import WorldCore

/// Durable character sessions: one document per session, keyed by session ID, so the Viewer can
/// show who was logged in and when even after a session ends.
struct MongoCharacterSessionRepository: CharacterSessionRepository, Sendable {
    private let sessions: MongoCollection

    init(database: MongoDatabase) {
        sessions = database[MongoWorldCollection.characterSessions]
    }

    func session(for characterID: EntityID) async throws -> CharacterSession? {
        try await sessions.find(["character_id": characterID.rawValue], as: CharacterSession.self)
            .sort(["logged_in_at": -1, "_id": -1])
            .limit(1)
            .drain()
            .first
    }

    func session(id: CharacterSessionID) async throws -> CharacterSession? {
        try await sessions.findOne(["_id": id.rawValue], as: CharacterSession.self)
    }

    func save(_ session: CharacterSession) async throws {
        var document = try BSONEncoder().encode(session)
        document["_id"] = session.sessionID.rawValue
        try await sessions.upsert(document, where: ["_id": session.sessionID.rawValue])
    }

    func latestSessions() async throws -> [CharacterSession] {
        // Newest login first, then the first document per character is that character's latest.
        let all = try await sessions.find(as: CharacterSession.self)
            .sort(["logged_in_at": -1, "_id": -1])
            .limit(1_000)
            .drain()
        var seen: Set<EntityID> = []
        return all.filter { seen.insert($0.characterID).inserted }
    }
}
