import Common
import Foundation
import OSLog

struct ServerLogItemProcessor {

    static let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "ServerLog")

    static public func processServerLogItem(_ serverLogItem: ServerLogItem) {

        // Feed this to SwiftData so it shows up in the UI
        Task {
            do {
                let container = await SwiftDataStore.shared.container()
                let importer = ServerLogImporter(modelContainer: container)
                try await importer.addLog(serverLogItem)
            } catch {
                logger.warning(
                    "Failed to save server log to SwiftData: \(error.localizedDescription)")
            }
        }

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
