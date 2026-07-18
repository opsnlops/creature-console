import Common
import OSLog
import SwiftData
import SwiftUI

/// Shows the dialog provenance of a rendered animation: jump back to the source `DialogScript`,
/// re-render it in place, and listen to / export the audio. Rendered only when the animation
/// actually came from a dialog.
///
/// `source_script_id` is a *soft* pointer — the script may have been deleted — so "Open Dialog
/// Script" fetches lazily and falls back to the copy-on-write `source_script_turns` snapshot if
/// the script is gone (404). Animations rendered from inline turns have no script to open, so we
/// show the snapshot directly.
struct AnimationDialogProvenanceView: View {

    let metadata: Common.AnimationMetadata
    /// Called with a freshly-fetched animation after an in-place re-render so the editor can
    /// refresh its tracks without reopening.
    var onRerendered: ((Common.Animation) -> Void)? = nil

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "AnimationDialogProvenanceView")
    private let server = CreatureServerClient.shared
    private let audioManager = AudioManager.shared

    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    @State private var isLoading = false
    @State private var scriptToOpen: DialogScript? = nil
    @State private var showSnapshot = false
    @State private var statusMessage: String? = nil

    /// Plays the animation's *already-rendered* audio directly, so "hear what's there" doesn't go
    /// through the turns-based preview (which regenerates a fresh take when nothing's cached).
    @State private var audioStatus: String? = nil

    /// Take chosen in the embedded preview panel (drives preview/export of the snapshot turns).
    @State private var selectedGenerationId: DialogGenerationIdentifier? = nil

    var body: some View {
        if metadata.hasDialogProvenance {
            content
        }
    }

    private var content: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                provenanceCard

                if !metadata.soundFile.isEmpty {
                    renderedAudioCard
                }

                if let scriptId = metadata.sourceScriptIdentifier {
                    DialogRerenderButton(
                        scriptId: scriptId,
                        title: metadata.title,
                        onCompleted: { result in
                            Task { await refreshEditor(animationId: result.animationId) }
                        })
                }

                // Listen to / export the audio for the snapshot turns this animation was rendered
                // from. The 17-channel WAV is only available via the preview endpoint (turns-based),
                // so we drive all of it off the CoW snapshot.
                if let turns = metadata.sourceScriptTurns, !turns.isEmpty {
                    DialogPreviewPanel(
                        turns: turns, title: metadata.title,
                        selectedGenerationId: $selectedGenerationId)
                }
            }
        }
        .sheet(item: $scriptToOpen) { script in
            NavigationStack {
                DialogScriptEditor(existing: script, mode: .animationLinked)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { scriptToOpen = nil }
                        }
                    }
            }
            #if os(macOS)
                .frame(minWidth: 760, minHeight: 640)
            #endif
        }
    }

    /// Plays the animation's actual rendered audio (`metadata.soundFile`) via the server's small
    /// MP3 downmix — distinct from the "Listen & Export" panel below, which auditions turns-based
    /// *preview takes* and regenerates when none is cached. MP3 streams natively through AVPlayer,
    /// so playback starts immediately without pulling the hundreds-of-MB 17-channel source (which
    /// isn't meaningfully playable on 2-channel hardware anyway). Needs creature-server#57.
    private var renderedAudioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Rendered Audio", systemImage: "waveform").font(.headline)
                Spacer()
            }
            Text("Play the audio embedded in this animation — no re-rendering.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    playRenderedAudio()
                } label: {
                    Label("Play This Animation's Audio", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    audioManager.stopURLPlayback()
                    audioStatus = nil
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
            }
            if let audioStatus {
                Text(audioStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func playRenderedAudio() {
        let fileName = metadata.soundFile
        guard !fileName.isEmpty else { return }
        // The MP3 route's URL ends in `.mp3` (creature-server#57), so AVPlayer detects the format
        // and streams it — the ~5 MB mono downmix plays in about a second, no full download.
        switch server.getSoundRenditionURL(fileName, as: .mp3) {
        case .success(let url):
            audioStatus = "Playing…"
            if case .failure(let error) = audioManager.playURL(url) {
                audioStatus = "Playback failed: \(error.message)"
            }
        case .failure(let error):
            audioStatus =
                "Couldn't build the audio URL: \(ServerError.detailedMessage(from: error))"
        }
    }

    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Dialog Script", systemImage: "text.bubble").font(.headline)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
            }

            if let scriptId = metadata.sourceScriptIdentifier {
                Text("This animation was rendered from a saved dialog script.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    open(scriptId)
                } label: {
                    Label("Open Dialog Script", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            } else {
                Text("Rendered from an inline dialog — there's no saved script to open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Label(statusMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Show the CoW snapshot for inline renders, or as a fallback when the source script
            // has been deleted.
            if metadata.sourceScriptIdentifier == nil || showSnapshot {
                snapshot
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var snapshot: some View {
        if let turns = metadata.sourceScriptTurns, !turns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Snapshot of what was rendered")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(index + 1). \(creatureName(turn.creatureId))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(turn.text)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func creatureName(_ id: CreatureIdentifier) -> String {
        creatures.first(where: { $0.id == id })?.name ?? id
    }

    private func open(_ id: DialogScriptIdentifier) {
        isLoading = true
        statusMessage = nil
        Task {
            let result = await server.getDialogScript(id: id)
            await MainActor.run {
                isLoading = false
                switch result {
                case .success(let script):
                    scriptToOpen = script
                case .failure(.notFound):
                    showSnapshot = true
                    statusMessage =
                        "The source dialog script was deleted — showing the snapshot it was rendered from."
                case .failure(let error):
                    statusMessage = ServerError.detailedMessage(from: error)
                    logger.warning(
                        "failed to load source dialog script \(id): \(statusMessage ?? "")")
                }
            }
        }
    }

    private func refreshEditor(animationId: AnimationIdentifier) async {
        let result = await server.getAnimation(animationId: animationId)
        if case .success(let animation) = result {
            await MainActor.run { onRerendered?(animation) }
        }
    }
}
