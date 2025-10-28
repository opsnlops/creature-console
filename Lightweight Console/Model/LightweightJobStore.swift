import Common
import Foundation

actor LightweightJobStore {
    static let shared = LightweightJobStore()

    struct JobInfo: Identifiable, Equatable, Sendable {
        let jobId: String
        let jobType: JobType
        var status: JobStatus
        var progress: Double?
        var result: String?
        var rawDetails: String?
        var adHocResult: AdHocSpeechJobResult?
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

    private var jobs: [String: JobInfo] = [:]
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    private init() {}

    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation

            for job in jobs.values {
                continuation.yield(.updated(job))
            }

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
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
                adHocResult: nil,
                lastUpdated: Date()
            )

        info.status = progress.status
        info.progress = progress.progress
        info.rawDetails = progress.details ?? info.rawDetails
        info.lastUpdated = Date()

        jobs[progress.jobId] = info
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
                adHocResult: completion.decodeResult(as: AdHocSpeechJobResult.self),
                lastUpdated: Date()
            )

        info.status = completion.status
        info.progress = completion.status == .completed ? 1.0 : info.progress
        info.result = completion.result
        info.rawDetails = completion.details ?? info.rawDetails
        if let adHocResult = completion.decodeResult(as: AdHocSpeechJobResult.self) {
            info.adHocResult = adHocResult
        }
        info.lastUpdated = Date()

        jobs[completion.jobId] = info
        broadcast(.updated(info))
    }

    func remove(jobId: String) {
        guard jobs.removeValue(forKey: jobId) != nil else { return }
        broadcast(.removed(jobId))
    }

    private func broadcast(_ event: Event) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
