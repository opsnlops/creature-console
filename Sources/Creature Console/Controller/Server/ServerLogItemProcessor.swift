import Common
import Foundation
import OSLog

struct ServerLogItemProcessor {

    static let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "ServerLog")

    static public func processServerLogItem(_ serverLogItem: ServerLogItem) {

        // Feed this to the logManager so it shows up in the UI
        LogManager.shared.addLogMessage(from: serverLogItem)

        // Convert the level to our enum
        let level = ServerLogLevel(from: serverLogItem.level)

        switch level {
        case .debug:
            logger.debug("\(serverLogItem.message)")
        case .trace:
            logger.trace("\(serverLogItem.message)")
        case .info:
            logger.info("\(serverLogItem.message)")
        case .warn:
            logger.warning("\(serverLogItem.message)")
        case .error:
            logger.error("\(serverLogItem.message)")
        case .critical:
            logger.critical("\(serverLogItem.message)")
        case .off:
            break
        case .unknown:
            logger.debug("Server Unknown Level message: \(serverLogItem.message)")
        }


    }

}
