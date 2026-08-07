import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Renders the current scene into a multi-track Animation. Posts the async render job, then
/// watches `JobStatusStore` (fed by the websocket `job-progress`/`job-complete` stream) for
/// the matching `jobId`, showing live progress and a result summary.
///
/// `scriptId` is passed only when the in-memory scene exactly matches the saved server copy.
/// Final rendering requires that id and the exact full-dialog take the author auditioned, which
/// preserves provenance and prevents a partial/unsaved preview from becoming a final animation.
struct DialogRenderPanel: View {

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DialogRenderPanel")

    let scriptId: DialogScriptIdentifier?
    let turns: [DialogScriptTurn]
    let selectedGenerationId: DialogGenerationIdentifier?
    let defaultTitle: String
    let backgroundMusic: DialogBackgroundMusic?
    /// The stage saved on the script, which the server uses when the request doesn't override.
    let scriptStageId: StageIdentifier?

    private let server = CreatureServerClient.shared

    @State private var persistence: DialogPersistence = .permanent
    @State private var autoplay = false
    @State private var titleText = ""
    /// Per-render stage override; nil follows the script's own binding. This is how a travel
    /// rendition of a mainstage scene gets made without touching the saved script — the server
    /// keys rendered animations by (script, stage), so both renditions coexist.
    @State private var stageOverride: StageIdentifier? = nil

    @Query(sort: \StageModel.title) private var stageModels: [StageModel]

    @State private var activeJobId: String? = nil
    @State private var observedJob: JobStatusStore.JobInfo? = nil
    @State private var isSubmitting = false

    @State private var completedResult: DialogJobResult? = nil
    @State private var errorAlert: ErrorAlert?
    @State private var renderedSoundToShare: String? = nil

    /// What "no override" means right now, so the menu reads as a statement of fact rather than
    /// a mystery default.
    private var followScriptLabel: String {
        guard let scriptStageId else { return "None — script has no stage" }
        let title = stageModels.first(where: { $0.id == scriptStageId })?.title
        return "Script's stage — \(title?.isEmpty == false ? title! : "(untitled)")"
    }

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

            if let backgroundMusic {
                Label(
                    "Final render includes accepted music on channel 17: \(backgroundMusic.soundFile)",
                    systemImage: "music.note"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "No background music is accepted; this render will contain dialog only.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if scriptId == nil || selectedGenerationId == nil {
                // This is the actionable blocker for the greyed-out Render button, so it reads
                // as one — not as passive info. Rendering goes by script id and picks up the
                // *saved* server copy, which is exactly why unsaved edits (including a freshly
                // chosen stage) must be saved first.
                Label(
                    scriptId == nil
                        ? "Unsaved changes — save the script, then render."
                        : "Generate and select a full-dialog voice take before final rendering.",
                    systemImage: scriptId == nil ? "square.and.arrow.down" : "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

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
                Text("Stage").frame(width: 90, alignment: .leading)
                Picker("Stage", selection: $stageOverride) {
                    Text(followScriptLabel).tag(StageIdentifier?.none)
                    ForEach(stageModels.filter { $0.id != scriptStageId }) { model in
                        Text("Override: \(model.title.isEmpty ? "(untitled)" : model.title)")
                            .tag(Optional(model.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if scriptStageId == nil && stageOverride == nil {
                Label(
                    "No stage — the cast won't look at each other. Bind one in the Stage section above for head aiming.",
                    systemImage: "eye.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .buttonStyle(.glassProminent)
                .disabled(
                    !turnsAreReady || isRendering || scriptId == nil
                        || selectedGenerationId == nil)

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
        .onAppear {
            // Pre-fill the title with the suggested scene name so it's a real, editable
            // value that's actually used — not just a grey placeholder that gets ignored.
            if titleText.isEmpty { titleText = defaultTitle }
        }
        .shareableSoundFlow(fileName: $renderedSoundToShare)
        .errorAlert($errorAlert)
        .watchJob(activeJobId) { info in
            observedJob = info
        } onTerminal: { info in
            observedJob = info
            handleTerminal(info)
        } onRemoved: {
        }
    }

    @ViewBuilder
    private func completionCard(_ result: DialogJobResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Render complete", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.subheadline.bold())
            Text(
                "\(result.numberOfFrames) frames • \(TimeHelper.formatDuration(result.durationSeconds)) • \(result.persistence)"
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
            if backgroundMusic != nil {
                Text(
                    "The duration includes the full dialog and the accepted music. A music-only outro is preserved; it is not trimmed to the last spoken line."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button {
                shareRenderedSound(result)
            } label: {
                Label(
                    "Generate Shareable Version of Sound…",
                    systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular.tint(.green.opacity(0.25)), in: .rect(cornerRadius: 10))
    }

    // MARK: - Actions

    private func render() {
        guard turnsAreReady, let scriptId, selectedGenerationId != nil else { return }
        isSubmitting = true
        observedJob = nil
        completedResult = nil

        // Fall back to the suggested title (the script/scene name) when the field is
        // left blank, so a dialog render is never saved as "Dialog <uuid>".
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = defaultTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = trimmedTitle.isEmpty ? fallback : trimmedTitle
        let title = effectiveTitle.isEmpty ? nil : effectiveTitle

        // nil override omits stage_id and the server falls back to the script's own binding —
        // read *at render time* from the saved script, the single source of truth. Resolving it
        // client-side here would silently render with a stale binding whenever another device
        // rebound the script. Requires the creature-server#128 fallback fix.
        let request = DialogRequest.fromScript(
            scriptId, persistence: persistence, autoplay: autoplay, title: title,
            generationId: selectedGenerationId, stageId: stageOverride)

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
                    errorAlert = ErrorAlert(title: "Render Error", error: error)
                }
            }
        }
    }

    private func handleTerminal(_ info: JobStatusStore.JobInfo) {
        switch info.status {
        case .completed:
            completedResult = info.dialogResult
        case .failed:
            errorAlert = ErrorAlert(
                title: "Render Error",
                message: info.result ?? "The dialog render failed on the server.")
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
                        errorAlert = ErrorAlert(
                            title: "Render Error",
                            message: "This animation doesn't have a sound file to share.")
                    } else {
                        renderedSoundToShare = animation.metadata.soundFile
                    }
                case .failure(let error):
                    errorAlert = ErrorAlert(title: "Render Error", error: error)
                }
            }
        }
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
