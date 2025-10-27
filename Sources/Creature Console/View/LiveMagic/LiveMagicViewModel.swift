import Common
import Foundation
import SwiftUI

@MainActor
final class LiveMagicViewModel: ObservableObject {

    enum PromptMode: Equatable {
        case instant
        case cue

        var title: String {
            switch self {
            case .instant:
                return "Instant Speech"
            case .cue:
                return "Cue Speech"
            }
        }

        var description: String {
            switch self {
            case .instant:
                return "Generate speech and play it immediately."
            case .cue:
                return "Generate speech, hold it, and play it when you're ready."
            }
        }

        var submitLabel: String {
            switch self {
            case .instant:
                return "Start Performing"
            case .cue:
                return "Build Cue"
            }
        }
    }

    struct PromptRequest: Equatable {
        let creature: Creature
        let text: String
        let resumePlaylist: Bool
    }

    struct PreparedCue: Identifiable, Equatable {
        let id: String
        let jobId: String
        let animationId: String
        let creatureName: String
        let script: String
        let soundFile: String
        let createdAt: Date
        let defaultResumePlaylist: Bool
    }

    struct JobCard: Identifiable, Equatable {
        let id: String
        let context: SubmissionContext
        let status: JobStatus
        let progress: Double?
        let message: String?
        let isTerminal: Bool
        let updatedAt: Date
    }

    struct AlertDescriptor: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    struct SubmissionContext: Equatable {
        let jobId: String
        let mode: PromptMode
        let creature: Creature
        let text: String
        let resumePlaylist: Bool
        let createdAt: Date
    }

    @Published var isPresentingPrompt: Bool = false
    @Published private(set) var promptMode: PromptMode = .instant
    @Published private(set) var jobCards: [JobCard] = []
    @Published private(set) var preparedCues: [PreparedCue] = []
    @Published private(set) var isSubmittingPrompt: Bool = false
    @Published var alert: AlertDescriptor?

    private let server: CreatureServerClient
    private var submissionContexts: [String: SubmissionContext] = [:]
    private var jobInfos: [String: JobStatusStore.JobInfo] = [:]
    private var jobEventsTask: Task<Void, Never>?
    private var hiddenJobIds: Set<String> = []

    init(server: CreatureServerClient = .shared) {
        self.server = server
        observeJobEvents()
    }

    deinit {
        jobEventsTask?.cancel()
    }

    func presentPrompt(for mode: PromptMode) {
        promptMode = mode
        isPresentingPrompt = true
    }

    func dismissPrompt() {
        isPresentingPrompt = false
    }

    func submitPrompt(_ request: PromptRequest) async {
        guard !isSubmittingPrompt else { return }
        isSubmittingPrompt = true

        let submissionMode = promptMode
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            isSubmittingPrompt = false
            alert = AlertDescriptor(
                title: "Missing Dialog",
                message: "Enter the lines you want \(request.creature.name) to deliver."
            )
            return
        }

        let result: Result<JobCreatedResponse, ServerError>
        switch submissionMode {
        case .instant:
            result = await server.createAdHocSpeechAnimation(
                creatureId: request.creature.id,
                text: text,
                resumePlaylist: request.resumePlaylist
            )
        case .cue:
            result = await server.prepareAdHocSpeechAnimation(
                creatureId: request.creature.id,
                text: text,
                resumePlaylist: request.resumePlaylist
            )
        }

        switch result {
        case .success(let response):
            let context = SubmissionContext(
                jobId: response.jobId,
                mode: submissionMode,
                creature: request.creature,
                text: text,
                resumePlaylist: request.resumePlaylist,
                createdAt: Date()
            )
            submissionContexts[response.jobId] = context
            updateJobCards()
            dismissPrompt()
            alert = AlertDescriptor(
                title: "Job Queued",
                message: response.message
            )
        case .failure(let error):
            alert = AlertDescriptor(
                title: "Unable to Queue",
                message: ServerError.detailedMessage(from: error)
            )
        }

        isSubmittingPrompt = false
    }

    func dismissJobCard(id: String) {
        if let info = jobInfos[id], !info.isTerminal {
            hiddenJobIds.insert(id)
            updateJobCards()
            return
        }

        submissionContexts.removeValue(forKey: id)
        jobInfos.removeValue(forKey: id)
        hiddenJobIds.remove(id)
        updateJobCards()
        Task {
            await JobStatusStore.shared.remove(jobId: id)
        }
    }

    func removeCue(_ cue: PreparedCue) {
        preparedCues.removeAll { $0.id == cue.id }
    }

    func playCue(_ cue: PreparedCue, resumePlaylist: Bool) async {
        let result = await server.triggerPreparedAdHocSpeech(
            animationId: cue.animationId,
            resumePlaylist: resumePlaylist
        )

        switch result {
        case .success(let message):
            alert = AlertDescriptor(title: "Cue Sent", message: message)
            removeCue(cue)
        case .failure(let error):
            alert = AlertDescriptor(
                title: "Playback Failed",
                message: ServerError.detailedMessage(from: error)
            )
        }
    }

    private func observeJobEvents() {
        jobEventsTask = Task { [weak self] in
            let stream = await JobStatusStore.shared.events()
            for await event in stream {
                guard let self else { return }
                await MainActor.run {
                    self.handle(jobEvent: event)
                }
            }
        }
    }

    private func handle(jobEvent: JobStatusStore.Event) {
        switch jobEvent {
        case .updated(let info)
        where info.jobType == .adHocSpeech || info.jobType == .adHocSpeechPrepare:
            jobInfos[info.jobId] = info
            if info.isTerminal {
                handleTerminalState(for: info)
                hiddenJobIds.remove(info.jobId)
            }
            updateJobCards()
        case .removed(let jobId):
            jobInfos.removeValue(forKey: jobId)
            submissionContexts.removeValue(forKey: jobId)
            updateJobCards()
        default:
            break
        }
    }

    private func handleTerminalState(for info: JobStatusStore.JobInfo) {
        guard let context = submissionContexts[info.jobId] else { return }

        if info.jobType == .adHocSpeechPrepare,
            info.status == .completed,
            let result = info.adHocResult
        {
            let cue = PreparedCue(
                id: result.animationId,
                jobId: info.jobId,
                animationId: result.animationId,
                creatureName: context.creature.name,
                script: context.text,
                soundFile: result.soundFile,
                createdAt: Date(),
                defaultResumePlaylist: result.resumePlaylist
            )
            preparedCues.removeAll { $0.id == cue.id }
            preparedCues.insert(cue, at: 0)
            submissionContexts.removeValue(forKey: info.jobId)
        } else if info.jobType == .adHocSpeech {
            // Automatic playback jobs can be cleared once the result is captured.
            if info.status == .completed {
                alert = AlertDescriptor(
                    title: "Performance Started",
                    message: info.result ?? "\(context.creature.name) is performing now."
                )
            } else if info.status == .failed {
                alert = AlertDescriptor(
                    title: "Ad-Hoc Speech Failed",
                    message: info.result ?? "Something went wrong while generating the animation."
                )
            }
            submissionContexts.removeValue(forKey: info.jobId)
        }

        Task {
            await JobStatusStore.shared.remove(jobId: info.jobId)
        }
    }

    private func updateJobCards() {
        var cards: [JobCard] = []
        for (jobId, context) in submissionContexts {
            let info = jobInfos[jobId]
            let progress = info?.progressPercentage.map { $0 / 100.0 }
            let message = info?.result ?? info?.rawDetails
            let status = info?.status ?? .queued
            let updatedAt = info?.lastUpdated ?? context.createdAt
            let isHidden = hiddenJobIds.contains(jobId) && !(info?.isTerminal ?? false)
            if isHidden { continue }

            let card = JobCard(
                id: jobId,
                context: context,
                status: status,
                progress: progress,
                message: message,
                isTerminal: info?.isTerminal ?? false,
                updatedAt: updatedAt
            )
            cards.append(card)
        }

        jobCards = cards.sorted { $0.updatedAt > $1.updatedAt }
    }
}
