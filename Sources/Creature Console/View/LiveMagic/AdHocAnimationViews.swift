// AdHocAnimationViews.swift
// Extracted from AdHocAssetsView.swift (Phase 5 decomposition, issue #35).

import Common
import PlaylistRuntime
import SwiftUI

private typealias CreatureAnimation = Common.Animation

struct AdHocAnimationListView: View {

    private let server = CreatureServerClient.shared

    @State private var animations: [AdHocAnimationSummary] = []
    @State private var isLoading = false
    @State private var errorAlert: ErrorAlert?
    @PlaylistResumePreference private var resumePlaylistAfterPlayback: Bool
    @State private var playingAnimationId: AnimationIdentifier?
    @State private var playTask: Task<Void, Never>?

    var body: some View {
        List {
            if isLoading && animations.isEmpty {
                ProgressView("Loading ad-hoc animations…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if animations.isEmpty {
                ContentUnavailableView(
                    "No Ad-Hoc Animations",
                    systemImage: "sparkles",
                    description:
                        Text("Generate one from the Live Magic console to see it here.")
                )
            } else {
                ForEach(
                    animations.sorted {
                        ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                ) { animation in
                    AdHocAnimationRow(
                        animation: animation,
                        playAction: {
                            triggerPlayback(for: animation.animationId)
                        },
                        isPlaying: playingAnimationId == animation.animationId
                    )
                }
            }
        }
        #if os(macOS)
            .listStyle(.inset)
        #elseif os(tvOS)
            .listStyle(.plain)
        #else
            .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Ad-Hoc Animations")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task { await load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help("Refresh the ad-hoc animation list")

                #if os(macOS)
                    Menu {
                        Toggle(
                            "Resume playlist after playback",
                            isOn: $resumePlaylistAfterPlayback
                        )
                    } label: {
                        Label("Playback Options", systemImage: "slider.horizontal.3")
                    }
                    .help("Configure how ad-hoc playback interacts with playlists")
                #endif
            }
        }
        .refreshable {
            await load(force: true)
        }
        .task {
            await load()
        }
        .onDisappear {
            playTask?.cancel()
            playTask = nil
        }
        .errorAlert($errorAlert)
    }

    private func triggerPlayback(for animationId: AnimationIdentifier) {
        playTask?.cancel()
        playTask = Task {
            await play(animationId: animationId)
        }
    }

    private func play(animationId: AnimationIdentifier) async {
        playingAnimationId = animationId

        let result = await PlaylistRuntimeActions.playPreparedAdHoc(animationId: animationId)

        if playingAnimationId == animationId {
            playingAnimationId = nil
        }
        playTask = nil
        switch result {
        case .success:
            errorAlert = nil
        case .failure(let error):
            errorAlert = ErrorAlert(title: "Unable to Load", error: error)
        }
    }

    private func load(force: Bool = false) async {
        if isLoading && !force { return }
        isLoading = true
        let result = await server.listAdHocAnimations()
        isLoading = false
        switch result {
        case .success(let list):
            animations = list
            errorAlert = nil
        case .failure(let error):
            errorAlert = ErrorAlert(title: "Unable to Load", error: error)
        }
    }
}

private struct AdHocAnimationRow: View {
    let animation: AdHocAnimationSummary
    let playAction: (() -> Void)?
    let isPlaying: Bool

    init(
        animation: AdHocAnimationSummary,
        playAction: (() -> Void)? = nil,
        isPlaying: Bool = false
    ) {
        self.animation = animation
        self.playAction = playAction
        self.isPlaying = isPlaying
    }

    var body: some View {
        #if os(macOS)
            HStack(alignment: .center, spacing: 12) {
                navigationLink
                if let playAction {
                    Button(action: playAction) {
                        if isPlaying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Play", systemImage: "play.fill")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .disabled(isPlaying)
                    .help("Play this ad-hoc animation on the connected creature")
                }
            }
            .contextMenu {
                if let playAction {
                    Button {
                        playAction()
                    } label: {
                        Label("Play on Server", systemImage: "play.fill")
                    }
                    .disabled(isPlaying)
                }
                copyIdButton
            }
        #else
            navigationLink
                .contextMenu {
                    if let playAction {
                        Button {
                            playAction()
                        } label: {
                            Label("Play on Server", systemImage: "play.fill")
                        }
                        .disabled(isPlaying)
                    }
                    copyIdButton
                }
        #endif
    }

    private var navigationLink: some View {
        NavigationLink {
            AdHocAnimationDetailView(animationId: animation.animationId)
        } label: {
            rowContent
        }
        #if os(macOS)
            .buttonStyle(.plain)
        #endif
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(animation.metadata.title)
                        .font(.headline)
                    if let createdAt = animation.createdAt {
                        Text(adHocRelativeString(createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(animation.animationId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        #if !os(tvOS)
                            .textSelection(.enabled)
                        #endif
                    if !animation.metadata.soundFile.isEmpty {
                        Label(animation.metadata.soundFile, systemImage: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            Text(animation.metadata.note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label("\(animation.metadata.numberOfFrames) frames", systemImage: "film")
                    .font(.caption)
                Label("\(animation.metadata.millisecondsPerFrame)ms", systemImage: "speedometer")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var copyIdButton: some View {
        Button {
            Pasteboard.copy(animation.animationId)
        } label: {
            Label("Copy Animation ID", systemImage: "doc.on.doc")
        }
    }
}

private struct AdHocAnimationDetailView: View {

    let animationId: AnimationIdentifier
    @State private var animation: CreatureAnimation?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading animation…")
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if let animation {
                #if os(iOS) || os(macOS)
                    AnimationEditor(animation: animation, readOnly: true)
                #else
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Preview Unavailable")
                                .font(.title2.weight(.semibold))
                            Text(
                                "Ad-hoc animation playback requires the full editor, which is currently unavailable on this platform."
                            )
                            .font(.body)
                            .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                #endif
            }
        }
        .navigationTitle("Ad-Hoc Animation")
        .task(id: animationId) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        let result = await CreatureServerClient.shared.getAdHocAnimation(animationId: animationId)
        isLoading = false
        switch result {
        case .success(let animation):
            self.animation = animation
        case .failure(let error):
            errorMessage = ServerError.detailedMessage(from: error)
        }
    }
}
