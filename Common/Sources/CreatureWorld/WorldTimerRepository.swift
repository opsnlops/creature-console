import Foundation
import MongoKitten
import WorldCore

struct WorldTimerRepository: Sendable {
    private let timers: MongoCollection

    init(database: MongoDatabase) {
        self.timers = database[MongoWorldCollection.timers]
    }

    func schedule(_ timer: WorldTimer) async throws {
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

    func cancel(timerID: TimerID, canceledAt: Date) async throws -> Bool {
        let values: Document = [
            "status": WorldTimerStatus.canceled.rawValue,
            "canceled_at": canceledAt,
        ]
        let builder = timers.findOneAndUpdate(
            where: [
                "_id": timerID.rawValue,
                "status": WorldTimerStatus.pending.rawValue,
            ],
            to: ["$set": values],
            returnValue: .modified
        )
        return try await builder.writeConcern(.majority()).decode(WorldTimer.self) != nil
    }

    func recoverable(limit: Int) async throws -> [WorldTimer] {
        precondition(limit > 0)
        let statuses: Document = [
            "$in": [WorldTimerStatus.pending.rawValue, WorldTimerStatus.firing.rawValue]
        ]
        return try await timers.find(["status": statuses], as: WorldTimer.self)
            .sort(["due_at": 1, "timer_id": 1])
            .limit(limit)
            .drain()
    }

    func claim(timerID: TimerID, dueAt: Date, firingAt: Date) async throws -> WorldTimer? {
        guard dueAt <= firingAt else { return nil }
        let statuses: Document = [
            "$in": [WorldTimerStatus.pending.rawValue, WorldTimerStatus.firing.rawValue]
        ]
        let values: Document = [
            "status": WorldTimerStatus.firing.rawValue,
            "firing_at": firingAt,
        ]
        let builder = timers.findOneAndUpdate(
            where: [
                "_id": timerID.rawValue,
                "due_at": dueAt,
                "status": statuses,
            ],
            to: ["$set": values],
            returnValue: .modified
        )
        return try await builder.writeConcern(.majority()).decode(WorldTimer.self)
    }

    func markFired(timerID: TimerID, dueAt: Date, firedAt: Date) async throws -> Bool {
        let values: Document = [
            "status": WorldTimerStatus.fired.rawValue,
            "fired_at": firedAt,
        ]
        let builder = timers.findOneAndUpdate(
            where: [
                "_id": timerID.rawValue,
                "due_at": dueAt,
                "status": WorldTimerStatus.firing.rawValue,
            ],
            to: ["$set": values],
            returnValue: .modified
        )
        return try await builder.writeConcern(.majority()).decode(WorldTimer.self) != nil
    }

    // Compatibility alias for existing repository callers.
    func save(_ timer: WorldTimer) async throws {
        try await schedule(timer)
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
