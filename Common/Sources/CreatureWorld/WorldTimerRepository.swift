import Foundation
import MongoKitten
import WorldCore

struct WorldTimerRepository: Sendable {
    private let timers: MongoCollection

    init(database: MongoDatabase) {
        self.timers = database[MongoWorldCollection.timers]
    }

    func save(_ timer: WorldTimer) async throws {
        var document = try BSONEncoder().encode(timer)
        document["_id"] = timer.timerID.rawValue
        _ = try await timers.findOneAndUpsert(
            where: ["_id": timer.timerID.rawValue],
            replacement: document,
            returnValue: .modified
        )
        .writeConcern(.majority())
        .execute()
    }

    func pending(dueBefore: Date? = nil) async throws -> [WorldTimer] {
        var query: Document = ["status": WorldTimerStatus.pending.rawValue]
        if let dueBefore {
            let due: Document = ["$lte": dueBefore]
            query["due_at"] = due
        }
        return try await timers.find(query, as: WorldTimer.self).sort(["due_at": 1]).drain()
    }
}
