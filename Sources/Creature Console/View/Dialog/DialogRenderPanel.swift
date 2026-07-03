import Common
import Foundation
import OSLog
import SwiftUI

/// Renders the current scene into a multi-track Animation. Posts the async render job, then
/// watches `JobStatusStore` (fed by the websocket `job-progress`/`job-complete` stream) for
/// the matching `jobId`, showing live progress and a result summary.
///
/// `scriptId` is passed only when the in-memory scene exactly matches the saved server copy —
/// rendering by script id captures provenance (`source_script_id`) on the animation. When the
/// scene is unsaved or has unsaved edits, the caller passes `nil` and we render the inline
/// turns so the rendered audio always matches what the author sees.
struct DialogRenderPanel: View {

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DialogRenderPanel")

    let scriptId: DialogScriptIdentifier?
    let turns: [DialogScriptTurn]
    let selectedGenerationId: DialogGenerationIdentifier?
    let defaultTitle: String

    private let server = CreatureServerClient.shared

    @State private var persistence: DialogPersistence = .permanent
    @State private var autoplay = false
    @State private var titleText = ""

    @State private var activeJobId: String? = nil
    @State private var observedJob: JobStatusStore.JobInfo? = nil
    @State private var jobEventsTask: Task<Void, Never>? = nil
    @State private var isSubmitting = false

    @State private var completedResult: DialogJobResult? = nil
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var renderedSoundToShare: String? = nil

    private var turnsAreReady: Bool {
        !turns.isEmpty
            && turns.allSatisfy {
                !$0.creatureId.trimmingCharacters(in: .whitespaces).isEmpty
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private var isRendering: Bool {
        isSubmitting || (observedJob.map { !$0.isTerminal } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Render").font(.headline)

            HStack {
                Text("Storage").frame(width: 90, alignment: .leading)
                Picker("Storage", selection: $persistence) {
                    Text("Permanent").tag(DialogPersistence.permanent)
                    Text("Ad-hoc (temporary)").tag(DialogPersistence.adhoc)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Text("Title").frame(width: 90, alignment: .leading)
                TextField(defaultTitle.isEmpty ? "Animation title" : defaultTitle, text: $titleText)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Autoplay when rendered", isOn: $autoplay)
                .help(
                    "Plays immediately on the hardware once rendered. Requires every creature to be registered on the same universe."
                )

            HStack {
                Button {
                    render()
                } label: {
                    Label("Render Dialog", systemImage: "film")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!turnsAreReady || isRendering)

                if isRendering {
                    ProgressView().controlSize(.small)
                }
            }

            if let job = observedJob, !job.isTerminal {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: (job.progress ?? 0).clampedUnitInterval)
                    Text(progressMilestone(job.progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let result = completedResult {
                completionCard(result)
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .shareableSoundFlow(fileName: $renderedSoundToShare)
        .alert("Render Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task(id: activeJobId) {
            jobEventsTask?.cancel()
            guard let jobId = activeJobId else { return }
            jobEventsTask = Task {
                for await event in await JobStatusStore.shared.events(forJob: jobId) {
                    switch event {
                    case .updated(let info):
                        await MainActor.run { observedJob = info }
                    case .terminal(let info):
                        await MainActor.run {
                            observedJob = info
                            handleTerminal(info)
                        }
                    case .removed:
                        break
                    }
                }
            }
        }
        .onDisappear {
            jobEventsTask?.cancel()
            jobEventsTask = nil
        }
    }

    @ViewBuilder
    private func completionCard(_ result: DialogJobResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Render complete", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.subheadline.bold())
            Text(
                "\(result.numberOfFrames) frames • \(formatDuration(result.durationSeconds)) • \(result.persistence)"
                    + (result.autoplayed ? " • autoplayed" : "")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("Animation ID:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.animationId)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Text("The rendered animation is now in your Animations list.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                shareRenderedSound(result)
            } label: {
                Label("Generate Shareable Version…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular.tint(.green.opacity(0.25)), in: .rect(cornerRadius: 10))
    }

    // MARK: - Actions

    private func render() {
        guard turnsAreReady else { return }
        isSubmitting = true
        observedJob = nil
        completedResult = nil

        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? nil : trimmedTitle

        let request: DialogRequest
        if let scriptId {
            request = .fromScript(
                scriptId, persistence: persistence, autoplay: autoplay, title: title,
                generationId: selectedGenerationId)
        } else {
            request = .fromTurns(
                turns, persistence: persistence, autoplay: autoplay, title: title,
                generationId: selectedGenerationId)
        }

        Task {
            let result = await server.renderDialog(request)
            await MainActor.run {
                isSubmitting = false
                switch result {
                case .success(let job):
                    logger.info("dialog render job queued: \(job.jobId)")
                    Task {
                        await JobStatusStore.shared.seedQueued(job)
                    }
                    activeJobId = job.jobId
                case .failure(let error):
                    presentError(ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func handleTerminal(_ info: JobStatusStore.JobInfo) {
        switch info.status {
        case .completed:
            completedResult = info.dialogResult
            // A permanent render writes to the main animation + sound collections; refresh both
            // so the new animation shows up without waiting on the websocket invalidation.
            CacheInvalidationProcessor.rebuildAnimationCache(deleteStaleEntries: true)
            CacheInvalidationProcessor.rebuildSoundListCache(deleteStaleEntries: true)
        case .failed:
            presentError(info.result ?? "The dialog render failed on the server.")
        default:
            break
        }
        activeJobId = nil
    }

    /// The dialog result carries the animation id, not the sound file — look the
    /// animation up (in the store matching its persistence) to find what to share.
    private func shareRenderedSound(_ result: DialogJobResult) {
        Task {
            let animationResult =
                result.persistence == "adhoc"
                ? await server.getAdHocAnimation(animationId: result.animationId)
                : await server.getAnimation(animationId: result.animationId)
            await MainActor.run {
                switch animationResult {
                case .success(let animation):
                    if animation.metadata.soundFile.isEmpty {
                        presentError("This animation doesn't have a sound file to share.")
                    } else {
                        renderedSoundToShare = animation.metadata.soundFile
                    }
                case .failure(let error):
                    presentError(ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func progressMilestone(_ progress: Double?) -> String {
        guard let progress else { return "Working…" }
        switch progress {
        case ..<0.55: return "Generating voices…"
        case ..<0.60: return "Aligning audio…"
        case ..<0.70: return "Slicing per-creature tracks…"
        case ..<0.85: return "Assembling multi-track animation…"
        case ..<1.0: return "Saving…"
        default: return "Done"
        }
    }
}

extension Double {
    /// Clamp to the `0...1` range expected by `ProgressView(value:)`.
    fileprivate var clampedUnitInterval: Double { min(max(self, 0), 1) }
}
