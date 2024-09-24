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

class CreatureHealthCache: ObservableObject {
    static let shared = CreatureHealthCache()
    @Published private var motorSensorCache: [CreatureIdentifier: [MotorSensorReport]] = [:]
    @Published private var boardSensorCache: [CreatureIdentifier: [BoardSensorReport]] = [:]

    private let maxSensorCount = 100

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CreatureHealthCache")
    private let queue = DispatchQueue(
        label: "io.opsnlops.CreatureConsole.CreatureHealthCache.queue", attributes: .concurrent)

    // Don't make more than one by accident
    private init() {}

    // Add a new MotorSensorData for a Creature
    func addMotorSensorData(_ sensorData: MotorSensorReport, forCreature creatureId: CreatureIdentifier) {
        queue.async(flags: .barrier) {
            // Work on a local copy of the array to modify it in the background thread
            var updatedCache = self.motorSensorCache[creatureId, default: []]
            updatedCache.append(sensorData)

            // Trim to keep only the most recent 100 sensor data points
            if updatedCache.count > self.maxSensorCount {
                updatedCache.removeFirst()
            }

            // Now, update the @Published property on the main thread
            DispatchQueue.main.async {
                self.motorSensorCache[creatureId] = updatedCache
                self.objectWillChange.send()  // Notify observers
            }
        }
    }

    // Add a new BoardSensorData for a Creature
    func addBoardSensorData(_ sensorData: BoardSensorReport, forCreature creatureId: CreatureIdentifier) {
        queue.async(flags: .barrier) {
            // Work on a local copy of the array to modify it in the background thread
            var updatedCache = self.boardSensorCache[creatureId, default: []]
            updatedCache.append(sensorData)

            // Trim to keep only the most recent 100 sensor data points
            if updatedCache.count > self.maxSensorCount {
                updatedCache.removeFirst()
            }

            // Now, update the @Published property on the main thread
            DispatchQueue.main.async {
                self.boardSensorCache[creatureId] = updatedCache
                self.objectWillChange.send()  // Notify observers
            }
        }
    }

    // Get the most recent MotorSensorData for a Creature
    func latestMotorSensorData(forCreature creatureId: CreatureIdentifier) -> Result<MotorSensorReport, CacheError> {
        return queue.sync {
            if let latestData = motorSensorCache[creatureId]?.last {
                return .success(latestData)
            } else {
                return .failure(.noDataForCreature)
            }
        }
    }

    // Get all MotorSensorData for a Creature, sorted by time
    func allMotorSensorData(forCreature creatureId: CreatureIdentifier) -> Result<[MotorSensorReport], CacheError> {
        return queue.sync {
            if let sensorData = motorSensorCache[creatureId], !sensorData.isEmpty {
                return .success(sensorData.sorted(by: { $0.timestamp < $1.timestamp }))
            } else {
                return .failure(.noDataForCreature)
            }
        }
    }

    // Get the most recent BoardSensorData for a Creature
    func latestBoardSensorData(forCreature creatureId: CreatureIdentifier) -> Result<BoardSensorReport, CacheError> {
        return queue.sync {
            if let latestData = boardSensorCache[creatureId]?.last {
                return .success(latestData)
            } else {
                return .failure(.noDataForCreature)
            }
        }
    }

    // Get all BoardSensorData for a Creature, sorted by time
    func allBoardSensorData(forCreature creatureId: CreatureIdentifier) -> Result<[BoardSensorReport], CacheError> {
        return queue.sync {
            if let sensorData = boardSensorCache[creatureId], !sensorData.isEmpty {
                return .success(sensorData.sorted(by: { $0.timestamp < $1.timestamp }))
            } else {
                return .failure(.noDataForCreature)
            }
        }
    }
}

