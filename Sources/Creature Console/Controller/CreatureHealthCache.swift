import Combine
import Common
import Foundation
import OSLog

enum CacheError: Error, CustomStringConvertible {
    case noDataForCreature

    var description: String {
        switch self {
        case .noDataForCreature:
            return "No data available for the specified creature."
        }
    }
}

struct CreatureHealthCacheState: Sendable {
    let motorSensorCache: [CreatureIdentifier: [MotorSensorReport]]
    let boardSensorCache: [CreatureIdentifier: [BoardSensorReport]]
}

actor CreatureHealthCache {
    static let shared = CreatureHealthCache()

    private var motorSensorCache: [CreatureIdentifier: [MotorSensorReport]] = [:]
    private var boardSensorCache: [CreatureIdentifier: [BoardSensorReport]] = [:]

    private let maxSensorCount = 1000

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CreatureHealthCache")

    // Broadcasting AsyncStream for UI updates
    private var subscribers: [UUID: AsyncStream<CreatureHealthCacheState>.Continuation] = [:]

    var stateUpdates: AsyncStream<CreatureHealthCacheState> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[id] = continuation

            // Send current state immediately to new subscriber
            let currentState = CreatureHealthCacheState(
                motorSensorCache: motorSensorCache,
                boardSensorCache: boardSensorCache
            )
            continuation.yield(currentState)

            continuation.onTermination = { @Sendable _ in
                Task { [id] in
                    await self.removeSubscriber(id)
                }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    func getCurrentState() -> CreatureHealthCacheState {
        CreatureHealthCacheState(
            motorSensorCache: motorSensorCache,
            boardSensorCache: boardSensorCache
        )
    }

    // Don't make more than one by accident
    private init() {}

    // Add a new MotorSensorData for a Creature
    func addMotorSensorData(
        _ sensorData: MotorSensorReport, forCreature creatureId: CreatureIdentifier
    ) {
        var updatedCache = motorSensorCache[creatureId, default: []]
        updatedCache.append(sensorData)

        // Trim to keep only the most recent sensor data points
        if updatedCache.count > maxSensorCount {
            updatedCache.removeFirst()
        }

        motorSensorCache[creatureId] = updatedCache
        publishState()
    }

    private func publishState() {
        let currentState = CreatureHealthCacheState(
            motorSensorCache: motorSensorCache,
            boardSensorCache: boardSensorCache
        )
        logger.debug(
            "CreatureHealthCache: Publishing state update to \(self.subscribers.count) subscribers - board sensors for \(self.boardSensorCache.keys.count) creatures"
        )

        // Broadcast to all active subscribers
        for continuation in subscribers.values {
            continuation.yield(currentState)
        }
    }

    // Add a new BoardSensorData for a Creature
    func addBoardSensorData(
        _ sensorData: BoardSensorReport, forCreature creatureId: CreatureIdentifier
    ) {
        logger.info("CreatureHealthCache: Adding board sensor data for creature \(creatureId)")
        var updatedCache = boardSensorCache[creatureId, default: []]
        updatedCache.append(sensorData)

        // Trim to keep only the most recent sensor data points
        if updatedCache.count > maxSensorCount {
            updatedCache.removeFirst()
        }

        boardSensorCache[creatureId] = updatedCache
        publishState()
    }

    // Get the most recent MotorSensorData for a Creature
    func latestMotorSensorData(forCreature creatureId: CreatureIdentifier) -> Result<
        MotorSensorReport, CacheError
    > {
        if let latestData = motorSensorCache[creatureId]?.last {
            return .success(latestData)
        } else {
            return .failure(.noDataForCreature)
        }
    }

    // Get all MotorSensorData for a Creature, sorted by time
    func allMotorSensorData(forCreature creatureId: CreatureIdentifier) -> Result<
        [MotorSensorReport], CacheError
    > {
        if let sensorData = motorSensorCache[creatureId], !sensorData.isEmpty {
            return .success(sensorData.sorted(by: { $0.timestamp < $1.timestamp }))
        } else {
            return .failure(.noDataForCreature)
        }
    }

    // Get the most recent BoardSensorData for a Creature
    func latestBoardSensorData(forCreature creatureId: CreatureIdentifier) -> Result<
        BoardSensorReport, CacheError
    > {
        if let latestData = boardSensorCache[creatureId]?.last {
            return .success(latestData)
        } else {
            return .failure(.noDataForCreature)
        }
    }

    // Get all BoardSensorData for a Creature, sorted by time
    func allBoardSensorData(forCreature creatureId: CreatureIdentifier) -> Result<
        [BoardSensorReport], CacheError
    > {
        if let sensorData = boardSensorCache[creatureId], !sensorData.isEmpty {
            return .success(sensorData.sorted(by: { $0.timestamp < $1.timestamp }))
        } else {
            return .failure(.noDataForCreature)
        }
    }
}
