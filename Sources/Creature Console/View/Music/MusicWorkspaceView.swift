import Common
import OSLog
import SwiftData
import SwiftUI

/// The sidebar's Music section: every dialog, with whether it has a voice to compose against
/// and whether music is already accepted. Picking one opens the composer for it. Music is
/// always fitted to a dialog's accepted voice, so this is a workspace over dialogs rather than
/// a free-standing jukebox.
struct MusicWorkspaceView: View {
    @Query(sort: \DialogScriptModel.title, order: .forward)
    private var scripts: [DialogScriptModel]

    var body: some View {
        NavigationStack {
            Group {
                if scripts.isEmpty {
                    ContentUnavailableView {
                        Label("No Dialogs Yet", systemImage: "music.note.list")
                    } description: {
                        Text(
                            "Music is composed against a dialog's accepted voice take. Write a dialog, accept a take, and come back here to score it."
                        )
                    } actions: {
                        NavigationLink {
                            DialogScriptEditor(createNew: true)
                        } label: {
                            Label("New Dialog", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                } else {
                    List(scripts) { script in
                        // Destination-style, for the same reason as MusicLibraryView.
                        NavigationLink {
                            MusicForDialogView(scriptId: script.id)
                        } label: {
                            row(for: script)
                        }
                    }
                }
            }
            .navigationTitle("Music")
            #if os(macOS)
                .navigationSubtitle(
                    "\(scripts.filter { $0.acceptedVoiceJSON != nil }.count) dialog(s) ready to score"
                )
            #endif
        }
    }

    @ViewBuilder
    private func row(for script: DialogScriptModel) -> some View {
        let hasVoice = script.acceptedVoiceJSON != nil
        HStack(spacing: 12) {
            Image(
                systemName: script.hasBackgroundMusic
                    ? "music.note" : (hasVoice ? "waveform" : "text.bubble")
            )
            .foregroundStyle(
                script.hasBackgroundMusic
                    ? Color.green : (hasVoice ? Color.accentColor : Color.secondary)
            )
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(script.title.isEmpty ? "Untitled" : script.title)
                Text(status(for: script, hasVoice: hasVoice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = script.updatedAtDate {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func status(for script: DialogScriptModel, hasVoice: Bool) -> String {
        let turns = "\(script.turnCount) turn(s)"
        if script.hasBackgroundMusic { return "\(turns) • music accepted" }
        if hasVoice { return "\(turns) • voice accepted, no music yet" }
        return "\(turns) • no accepted voice"
    }
}

/// The composer for one saved dialog, outside the editor. Reads the canonical script from the
/// server (the SwiftData row is a mirror, but promotion and clearing return canonical scripts
/// and this view must merge them the same way the editor does) and learns the current cache
/// key from the free takes lookup, so voice freshness is a real verdict rather than an
/// assumption.
struct MusicForDialogView: View {
    let scriptId: DialogScriptIdentifier

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MusicForDialogView")
    private let server = CreatureServerClient.shared

    @State private var script: DialogScript?
    @State private var currentCacheKey: String?
    @State private var loadError: String?
    @State private var isLoading = true

    private var subject: MusicSubject? {
        guard let script else { return nil }
        return MusicSubject(
            scriptId: script.id,
            title: script.title,
            acceptedVoice: script.acceptedVoice,
            voiceFreshness: script.acceptedVoice?.freshness(forCacheKey: currentCacheKey)
                ?? .stale,
            backgroundMusic: script.backgroundMusic,
            hasUnsavedChanges: false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let script, let subject {
                    scriptSummary(script)
                    MusicCreationView(
                        subject: subject,
                        onScriptUpdated: { canonical in
                            self.script = canonical
                        },
                        onMusicUpdated: { music in
                            self.script?.backgroundMusic = music
                        },
                        heading: nil)
                } else if isLoading {
                    ProgressView("Loading dialog…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Could Not Load Dialog", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.glassProminent)
                    }
                }
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle(script?.title.isEmpty == false ? script!.title : "Music")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let script {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        DialogScriptEditor(existing: script)
                    } label: {
                        Label("Open Dialog", systemImage: "text.bubble")
                    }
                }
            }
        }
        .task(id: scriptId) { await load() }
    }

    @ViewBuilder
    private func scriptSummary(_ script: DialogScript) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(script.turns.count) turn(s)", systemImage: "text.bubble")
                if let voice = script.acceptedVoice {
                    Label(
                        "Voice accepted \(voice.acceptedAtDate.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "waveform")
                    if voice.freshness(forCacheKey: currentCacheKey) == .stale {
                        Label("predates the current turns", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label("No accepted voice", systemImage: "waveform.slash")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            if let first = script.turns.first {
                Text("“\(first.text)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .panelCard()
    }

    private func load() async {
        isLoading = true
        loadError = nil
        switch await server.getDialogScript(id: scriptId) {
        case .success(let canonical):
            script = canonical
            // The takes lookup is free and returns sha256(turns) as the server computes it —
            // the only honest way to say whether the acceptance still matches the turns.
            if !canonical.turns.isEmpty {
                switch await server.dialogPreviewLookup(.fromTurns(canonical.turns)) {
                case .success(let lookup):
                    currentCacheKey = lookup.cacheKey
                case .failure(let error):
                    logger.warning(
                        "takes lookup failed for \(scriptId): \(ServerError.detailedMessage(from: error))"
                    )
                    currentCacheKey = nil
                }
            }
        case .failure(let error):
            loadError = ServerError.detailedMessage(from: error)
        }
        isLoading = false
    }
}
