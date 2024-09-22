import Combine
import Common
import Foundation
import OSLog

class CreatureHealthCache: ObservableObject {
    static let shared = CreatureHealthCache()

    @Published public private(set) var healths: [CreatureIdentifier: CreatureHealth] = [:]
    @Published public private(set) var empty: Bool = true

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CreatureHealthCache")
    private let queue = DispatchQueue(
        label: "io.opsnlops.CreatureConsole.CreatureHealthCache.queue", attributes: .concurrent)

    // Make sure we don't accidentally create two of these
    private init() {}

    func updateCreature(_ boardSensors: BoardSensorReport) {
        queue.async(flags: .barrier) {

            // See if it exists, and update if so
            if let health = self.healths[boardSensors.creatureId] {
                health.boardTemperature = boardSensors.boardTemperature
                health.boardPowerSensors = boardSensors.powerReports

                DispatchQueue.main.async {
                    self.healths[boardSensors.creatureId] = health
                    self.empty = false
                }
            }

            // It doesn't already exist, so let's make it
            else {
                let health = CreatureHealth(
                    id: boardSensors.creatureId,
                    boardTemperature: boardSensors.boardTemperature,
                    boardPowerSensors: boardSensors.powerReports,
                    motorSensors: [])

                DispatchQueue.main.async {
                    self.healths[boardSensors.creatureId] = health
                    self.empty = false
                }
            }

        }

    }

    func updateCreature(_ motorSensors: MotorSensorReport) {
        queue.async(flags: .barrier) {

            // See if it exists, and update if so
            if let health = self.healths[motorSensors.creatureId] {
                health.motorSensors = motorSensors.motors

                DispatchQueue.main.async {
                    self.healths[motorSensors.creatureId] = health
                    self.empty = false
                }
            }

            // It doesn't already exist, so let's make it
            else {
                let health = CreatureHealth(
                    id: motorSensors.creatureId,
                    boardTemperature: .nan,
                    boardPowerSensors: [],
                    motorSensors: motorSensors.motors)

                DispatchQueue.main.async {
                    self.healths[motorSensors.creatureId] = health
                    self.empty = false
                }
            }

        }

    }

    public func getById(id: CreatureIdentifier) -> Result<CreatureHealth, ServerError> {
        queue.sync {
            if let health = healths[id] {
                return .success(health)
            } else {
                logger.warning("Unable to find creature \(id) in the health cache")
                return .failure(.notFound("Unable to find creature \(id) in the health cache"))
            }
        }
    }
}
