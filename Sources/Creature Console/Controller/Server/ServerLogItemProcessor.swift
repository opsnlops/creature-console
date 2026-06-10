import Common
import Foundation
import OSLog

struct ServerLogItemProcessor {

    static let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "ServerLog")

    // One long-lived importer for the whole app. Creating a fresh @ModelActor (and its
    // ModelContext) for every log line is wasteful at log-burst rates, and any
    // per-instance state in the importer would never accumulate across instances.
    private static let sharedImporter = Task {
        ServerLogImporter(modelContainer: await SwiftDataStore.shared.container())
    }

    static public func processServerLogItem(_ serverLogItem: ServerLogItem) async {

        // Feed this to SwiftData so it shows up in the UI
        do {
            try await sharedImporter.value.addLog(serverLogItem)
        } catch {
            logger.warning(
                "Failed to save server log to SwiftData: \(error.localizedDescription)")
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
