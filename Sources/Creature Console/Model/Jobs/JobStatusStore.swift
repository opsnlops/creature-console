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
        var animationLipSyncDetails: AnimationLipSyncJobDetails?
        var animationLipSyncResult: AnimationLipSyncJobResult?
        var adHocResult: AdHocSpeechJobResult?
        var dialogResult: DialogJobResult?
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

    /// One job's lifecycle, as seen by a `events(forJob:)` watcher.
    enum JobWatchEvent: Sendable {
        /// Progress while the job is running (non-terminal).
        case updated(JobInfo)
        /// The job reached a terminal status. The store removes the job right after
        /// yielding this, and the stream finishes.
        case terminal(JobInfo)
        /// Someone else removed the job before it reached a terminal status. The
        /// stream finishes.
        case removed
    }

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "JobStatusStore")

    private var jobs: [String: JobInfo] = [:]
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    private init() {}

    func events() -> AsyncStream<Event> {
        // makeStream lets registration happen synchronously on the actor — with the old
        // `AsyncStream { Task { register(...) } }` shape, any event broadcast between stream
        // creation and that deferred hop was silently missed by the new subscriber.
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        register(continuation: continuation)
        return stream
    }

    /// Watch a single job — the one shared implementation of the subscribe/filter/finish
    /// dance every job panel needs. Replays the job's current state on subscription,
    /// yields `.updated` while it runs, then finishes after exactly one `.terminal`
    /// (auto-removing the job from the store) or `.removed`.
    func events(forJob jobId: String) -> AsyncStream<JobWatchEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await event in self.events() {
                    switch event {
                    case .updated(let info) where info.jobId == jobId:
                        if info.isTerminal {
                            continuation.yield(.terminal(info))
                            self.remove(jobId: jobId)
                            continuation.finish()
                            return
                        }
                        continuation.yield(.updated(info))
                    case .removed(let removedId) where removedId == jobId:
                        continuation.yield(.removed)
                        continuation.finish()
                        return
                    default:
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Seed the store with an optimistic queued/0.0 entry right after the server accepts
    /// a job (HTTP 202), so panels can show progress before the first websocket tick.
    /// Owns the details JSON encoding that call sites used to hand-roll. The terminal
    /// guard in `update(with:)` keeps this seed from resurrecting a fast job whose
    /// completion already arrived.
    func seedQueued(_ job: JobCreatedResponse, details: (any Encodable)? = nil) {
        var detailsString: String? = nil
        if let details, let data = try? JSONEncoder().encode(details) {
            detailsString = String(data: data, encoding: .utf8)
        }
        update(
            with: JobProgress(
                jobId: job.jobId,
                jobType: job.jobType,
                status: .queued,
                progress: 0,
                details: detailsString
            ))
    }

    func job(for id: String) -> JobInfo? {
        jobs[id]
    }

    func update(with progress: JobProgress) {
        // A terminal status is final. Completions arrive on the same ordered websocket
        // pipeline as progress, so the only out-of-order producer is a panel's optimistic
        // queued/0.0 seed racing a fast job's completion — letting it through would
        // resurrect the job as non-terminal and strand its observers.
        if let existing = jobs[progress.jobId], existing.isTerminal {
            logger.debug(
                "JobStatusStore: ignoring progress for terminal job \(progress.jobId)")
            return
        }
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
                animationLipSyncDetails: progress.decodeDetails(
                    as: AnimationLipSyncJobDetails.self),
                animationLipSyncResult: nil,
                adHocResult: nil,
                dialogResult: nil,
                lastUpdated: Date()
            )

        info.status = progress.status
        info.progress = progress.progress
        info.rawDetails = progress.details ?? info.rawDetails
        if info.lipSyncDetails == nil {
            info.lipSyncDetails = progress.decodeDetails(as: LipSyncJobDetails.self)
        }
        if info.animationLipSyncDetails == nil {
            info.animationLipSyncDetails = progress.decodeDetails(
                as: AnimationLipSyncJobDetails.self)
        }
        info.animationLipSyncResult = nil
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
                animationLipSyncDetails: completion.decodeDetails(
                    as: AnimationLipSyncJobDetails.self),
                animationLipSyncResult: completion.decodeResult(as: AnimationLipSyncJobResult.self),
                adHocResult: completion.decodeResult(as: AdHocSpeechJobResult.self),
                dialogResult: completion.decodeResult(as: DialogJobResult.self),
                lastUpdated: Date()
            )

        info.status = completion.status
        info.progress = completion.status == .completed ? 1.0 : info.progress
        info.result = completion.result
        info.rawDetails = completion.details ?? info.rawDetails
        if info.lipSyncDetails == nil {
            info.lipSyncDetails = completion.decodeDetails(as: LipSyncJobDetails.self)
        }
        if info.animationLipSyncDetails == nil {
            info.animationLipSyncDetails = completion.decodeDetails(
                as: AnimationLipSyncJobDetails.self)
        }
        if info.animationLipSyncResult == nil {
            info.animationLipSyncResult = completion.decodeResult(
                as: AnimationLipSyncJobResult.self)
        }
        if let adHocResult = completion.decodeResult(as: AdHocSpeechJobResult.self) {
            info.adHocResult = adHocResult
        }
        if let dialogResult = completion.decodeResult(as: DialogJobResult.self) {
            info.dialogResult = dialogResult
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
