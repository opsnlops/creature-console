import Common
import Foundation
import OSLog

struct JobStatusMessageProcessor {
    private static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "JobStatusMessageProcessor")

    static func processJobProgress(_ jobProgress: JobProgress) async {
        logger.debug(
            "Received job progress for \(jobProgress.jobId) status=\(jobProgress.status.rawValue)")
        await JobStatusStore.shared.update(with: jobProgress)
    }

    static func processJobCompletion(_ jobComplete: JobCompletion) async {
        logger.info(
            "Received job completion for \(jobComplete.jobId) status=\(jobComplete.status.rawValue)"
        )
        await JobStatusStore.shared.update(with: jobComplete)
    }
}
