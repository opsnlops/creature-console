import Common
import Foundation
import OSLog

actor JobStatusStore {
    static let shared = JobStatusStore()

    struct JobInfo: Identifiable, Equatable, Sendable {
        let jobId: String
        let jobType: JobType
        var status: JobStatus
        var progress: Double?
        var result: String?
        var rawDetails: String?
        var lipSyncDetails: LipSyncJobDetails?
        var lastUpdated: Date

        var id: String { jobId }

        var progressPercentage: Double? {
            guard let progress else { return nil }
            return min(max(progress * 100.0, 0.0), 100.0)
        }

        var isTerminal: Bool {
            status.isTerminal
        }
    }

    enum Event: Sendable {
        case updated(JobInfo)
        case removed(String)
    }

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "JobStatusStore")

    private var jobs: [String: JobInfo] = [:]
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    private init() {}

    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task { await self.register(continuation: continuation) }
        }
    }

    func job(for id: String) -> JobInfo? {
        jobs[id]
    }

    func update(with progress: JobProgress) {
        var info =
            jobs[progress.jobId]
            ?? JobInfo(
                jobId: progress.jobId,
                jobType: progress.jobType,
                status: progress.status,
                progress: progress.progress,
                result: nil,
                rawDetails: progress.details,
                lipSyncDetails: progress.decodeDetails(as: LipSyncJobDetails.self),
                lastUpdated: Date()
            )

        info.status = progress.status
        info.progress = progress.progress
        info.rawDetails = progress.details ?? info.rawDetails
        if info.lipSyncDetails == nil {
            info.lipSyncDetails = progress.decodeDetails(as: LipSyncJobDetails.self)
        }
        info.lastUpdated = Date()

        jobs[progress.jobId] = info
        logger.debug(
            "JobStatusStore: updated progress for job \(progress.jobId) (\(progress.status.rawValue))"
        )
        broadcast(.updated(info))
    }

    func update(with completion: JobCompletion) {
        var info =
            jobs[completion.jobId]
            ?? JobInfo(
                jobId: completion.jobId,
                jobType: completion.jobType,
                status: completion.status,
                progress: completion.status == .completed ? 1.0 : nil,
                result: completion.result,
                rawDetails: completion.details,
                lipSyncDetails: completion.decodeDetails(as: LipSyncJobDetails.self),
                lastUpdated: Date()
            )

        info.status = completion.status
        info.progress = completion.status == .completed ? 1.0 : info.progress
        info.result = completion.result
        info.rawDetails = completion.details ?? info.rawDetails
        if info.lipSyncDetails == nil {
            info.lipSyncDetails = completion.decodeDetails(as: LipSyncJobDetails.self)
        }
        info.lastUpdated = Date()

        jobs[completion.jobId] = info
        logger.debug(
            "JobStatusStore: recorded completion for job \(completion.jobId) (\(completion.status.rawValue))"
        )
        broadcast(.updated(info))
    }

    func remove(jobId: String) {
        guard jobs.removeValue(forKey: jobId) != nil else { return }
        logger.debug("JobStatusStore: removing job \(jobId)")
        broadcast(.removed(jobId))
    }

    private func register(continuation: AsyncStream<Event>.Continuation) {
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeContinuation(id) }
        }

        // Seed with current jobs so new listeners catch up immediately.
        for info in jobs.values {
            continuation.yield(.updated(info))
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcast(_ event: Event) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }
}
