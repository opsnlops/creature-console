import Common
import SwiftData
import SwiftUI

/// Couch audition: play accepted dialog voices and rendered dialog animations *spatially*,
/// positioned on their stages, out the Apple TV's HDMI port as discrete multichannel LPCM.
///
/// This is the whole point of the TV build of the spatial stack — an AirPlay'd Mac app is a
/// stereo pipe, but the same engine running here hands the Denon real channels. Ears only:
/// nothing on this screen edits anything, and only *chosen* audio (accepted voices, finished
/// renders) is offered — per-take candidate browsing stays in the dialog editor.
struct TVSpatialAuditionView: View {

    @Query(sort: \DialogScriptModel.title, order: .forward)
    private var scripts: [DialogScriptModel]

    @Query(sort: \AnimationMetadataModel.title, order: .forward)
    private var animations: [AnimationMetadataModel]

    @Query private var stages: [StageModel]

    private let localAudio = LocalAudioPlayer.shared

    @State private var nowPlayingTitle: String?
    @State private var errorMessage: String?
    @State private var showError = false

    /// A playable row: the file to position and the stage to position it on.
    private struct AuditionItem: Identifiable {
        let id: String
        let title: String
        let stageName: String
        let soundFile: String
        let stage: Stage
    }

    /// Scripts with an accepted, promoted voice file *and* a stage binding that resolves in
    /// the local mirror. The promoted file lives in the permanent sound store (`adHoc: false`).
    private var dialogItems: [AuditionItem] {
        scripts.compactMap { model in
            let script = model.toDTO()
            guard let soundFile = script.acceptedVoice?.soundFile, !soundFile.isEmpty,
                let stageId = script.stageId,
                let stageModel = stages.first(where: { $0.id == stageId })
            else { return nil }
            return AuditionItem(
                id: "dialog-\(script.id.uuidString)",
                title: script.title.isEmpty ? "Untitled" : script.title,
                stageName: stageModel.title,
                soundFile: soundFile,
                stage: stageModel.toDTO()
            )
        }
    }

    /// Rendered animations that came from a dialog on a known stage — their `soundFile` is the
    /// full multichannel WAV the server assembled, played back on the stage it was rendered for.
    private var animationItems: [AuditionItem] {
        animations.compactMap { animation in
            guard !animation.soundFile.isEmpty,
                let stageId = animation.sourceStageId.flatMap({ UUID(uuidString: $0) }),
                let stageModel = stages.first(where: { $0.id == stageId })
            else { return nil }
            return AuditionItem(
                id: "animation-\(animation.id)",
                title: animation.title.isEmpty ? "Untitled" : animation.title,
                stageName: stageModel.title,
                soundFile: animation.soundFile,
                stage: stageModel.toDTO()
            )
        }
    }

    var body: some View {
        Group {
            if dialogItems.isEmpty && animationItems.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Audition", systemImage: "person.wave.2")
                } description: {
                    Text(
                        "Accept a voice take on a stage-bound dialog, or render a dialog animation, and it will show up here for spatial playback through the receiver."
                    )
                }
            } else {
                List {
                    if localAudio.isPlaying, let nowPlayingTitle {
                        Section {
                            Button {
                                localAudio.stop()
                                self.nowPlayingTitle = nil
                            } label: {
                                Label {
                                    Text("Stop “\(nowPlayingTitle)”")
                                } icon: {
                                    Image(systemName: "stop.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        } header: {
                            Label("Now Playing", systemImage: "speaker.wave.3.fill")
                        }
                    }

                    if !dialogItems.isEmpty {
                        Section("Accepted Dialog Voices") {
                            ForEach(dialogItems) { item in
                                auditionRow(item, icon: "text.bubble")
                            }
                        }
                    }

                    if !animationItems.isEmpty {
                        Section("Rendered Dialog Animations") {
                            ForEach(animationItems) { item in
                                auditionRow(item, icon: "figure.socialdance")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Spatial Audition")
        .alert("Playback Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onDisappear {
            localAudio.stop()
        }
    }

    private func auditionRow(_ item: AuditionItem, icon: String) -> some View {
        Button {
            play(item)
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(item.title)
                        Text("Stage: \(item.stageName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon)
                        .symbolRenderingMode(.hierarchical)
                }
                Spacer()
                if localAudio.isPlaying, nowPlayingTitle == item.title {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func play(_ item: AuditionItem) {
        Task {
            do {
                // Accepted voices and finished renders both live in the permanent sound
                // store — the ad-hoc bucket only holds unpromoted take candidates, which
                // deliberately aren't offered here.
                try await localAudio.playSpatially(item.soundFile, stage: item.stage)
                nowPlayingTitle = item.title
            } catch {
                errorMessage = ServerError.detailedMessage(from: error)
                showError = true
            }
        }
    }
}
