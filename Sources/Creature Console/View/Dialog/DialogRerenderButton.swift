import Common
import OSLog
import SwiftUI

/// A self-contained "Re-render in Place" card for a saved dialog script.
///
/// Renders the script with `persistence: permanent`, which (server 3.15.4+) overwrites the
/// existing animation rendered from this script — the `animation_id` stays stable, so playlists
/// and triggers keep working. Observes the job via `JobStatusStore`, rebuilds the animation +
/// sound caches on completion, and calls `onCompleted` with the result (stable animation id).
///
/// Used both on an animation's provenance card and inside the script editor when it's opened
/// from an already-rendered animation (where a fresh "Render" would be the wrong affordance).
struct DialogRerenderButton: View {

    let scriptId: DialogScriptIdentifier
    let title: String
    /// Disable the action (e.g. while the script has unsaved edits a re-render wouldn't include).
    var disabled: Bool = false
    var disabledHint: String? = nil
    /// Called with the completed job result so a host can refresh the affected animation.
    var onCompleted: ((DialogJobResult) -> Void)? = nil

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DialogRerenderButton")
    private let server = CreatureServerClient.shared

    @State private var jobId: String? = nil
    @State private var progress: Double? = nil
    @State private var isRendering = false
    @State private var successMessage: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Re-render").font(.headline)
            Text(
                "Re-rendering overwrites this same animation in place — its ID stays valid for playlists and triggers."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    rerender()
                } label: {
                    Label("Re-render in Place", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRendering || disabled)

                if isRendering { ProgressView().controlSize(.small) }
            }

            if disabled, let disabledHint {
                Text(disabledHint).font(.caption).foregroundStyle(.secondary)
            }

            if isRendering, let progress {
                ProgressView(value: min(max(progress, 0), 1))
            }

            if let successMessage {
                Label(successMessage, systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .watchJob(jobId) { info in
            progress = info.progress
        } onTerminal: { info in
            handleTerminal(info)
        } onRemoved: {
        }
    }

    private func rerender() {
        isRendering = true
        successMessage = nil
        errorMessage = nil
        progress = 0
        let title = title
        Task {
            let result = await server.renderDialog(
                .fromScript(scriptId, persistence: .permanent, title: title))
            await MainActor.run {
                switch result {
                case .success(let job):
                    logger.info("in-place re-render job queued: \(job.jobId)")
                    Task {
                        await JobStatusStore.shared.seedQueued(job)
                    }
                    jobId = job.jobId
                case .failure(let error):
                    isRendering = false
                    errorMessage = ServerError.detailedMessage(from: error)
                }
            }
        }
    }

    private func handleTerminal(_ info: JobStatusStore.JobInfo) {
        jobId = nil
        isRendering = false
        progress = nil
        switch info.status {
        case .completed:
            successMessage = "Re-rendered in place — same animation ID, updated audio & tracks."
            CacheInvalidationProcessor.rebuildAfterDialogRender()
            if let result = info.dialogResult {
                onCompleted?(result)
            }
        case .failed:
            errorMessage = info.result ?? "The re-render failed on the server."
        default:
            break
        }
    }
}
