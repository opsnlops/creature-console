import AVFoundation
import Common
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// "Listen before you render" panel. Generates (or loads from cache) a preview take for the
/// current turns, plays the mono mixdown locally, lets the author flip between cached takes,
/// and exports the mono / 17-channel WAVs for inspection in Audacity.
///
/// Preview is always keyed by the in-memory `turns` (the server's cache key is `sha256(turns)`),
/// so the chosen `selectedGenerationId` lines up whether the eventual render goes by `script_id`
/// or inline turns.
struct DialogPreviewPanel: View {

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DialogPreviewPanel")

    let turns: [DialogScriptTurn]
    /// Scene title, embedded in the provenance of editor exports (#51). Empty when
    /// the editor has no title yet.
    var title: String = ""
    /// Partial previews are an authoring convenience. Only a full-dialog take can flow into
    /// music generation or the final render.
    @Binding var scope: DialogPreviewScope
    @Binding var fullDialogMeta: DialogPreviewMetaDTO?
    /// The take chosen here is shared with the render panel so a render uses exactly what was
    /// auditioned. `nil` means "latest / server decides".
    @Binding var selectedGenerationId: DialogGenerationIdentifier?
    /// Existing scripts should reopen on their latest cached take when one is available. New
    /// scripts remain intentionally blank until the author asks for a preview.
    var restoreCachedTake: Bool = false
    /// When a permanent dialog render has embedded its voice generation id, prefer that exact
    /// take over a newer unrelated preview cached for the same turns.
    var preferredGenerationId: DialogGenerationIdentifier? = nil

    private let server = CreatureServerClient.shared
    private let audioManager = AudioManager.shared

    @State private var isWorking = false
    @State private var statusMessage: String? = nil
    @State private var meta: DialogPreviewMetaDTO? = nil
    @State private var takes: [DialogPreviewLookupDTO.Generation] = []
    @State private var scopedGenerationId: DialogGenerationIdentifier? = nil
    /// Invalidates in-flight preview/lookup/export work when the turns or scope changes. The
    /// server request cannot always be cancelled once it is on the wire, so completions must
    /// also prove that they still belong to the current editor state before mutating the UI.
    @State private var requestToken = UUID()

    @State private var errorAlert: ErrorAlert?

    // Export state (cross-platform via .fileExporter)
    @State private var exportData: Data? = nil
    @State private var exportFilename = "dialog.wav"
    @State private var exportContentType: UTType = .wav
    @State private var showExporter = false

    private var previewTurns: [DialogScriptTurn] {
        scope.selectedTurns(from: turns) ?? []
    }

    /// Turn ids are client-only SwiftUI identities and are re-created whenever a canonical
    /// script is decoded after saving. The preview cache is keyed by wire content, so compare the
    /// same content here instead of the synthesized ids; otherwise a save clears the selected
    /// generation and makes the author open Find Takes again.
    private var turnContent: [String] {
        turns.map { "\($0.creatureId)\u{0}\($0.text)" }
    }

    private var turnsAreReady: Bool {
        !previewTurns.isEmpty
            && previewTurns.allSatisfy {
                !$0.creatureId.trimmingCharacters(in: .whitespaces).isEmpty
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("2. Voice Take").font(.title2.bold())
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }

            previewScopePicker

            if !scope.isFullDialog {
                Label(
                    "Partial previews are faster, but lose some cross-speaker reactivity. They cannot be used for music or final rendering.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !turnsAreReady {
                Text(
                    "Add at least one turn, with a creature and some text in each, to preview the audio."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    preview(regenerate: false)
                } label: {
                    Label("Preview", systemImage: "play.circle")
                }
                .disabled(!turnsAreReady || isWorking)

                Button {
                    preview(regenerate: true)
                } label: {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!turnsAreReady || isWorking)

                Button {
                    refreshTakes()
                } label: {
                    Label("Find Takes", systemImage: "square.stack.3d.up")
                }
                .disabled(!turnsAreReady || isWorking)
            }

            if let meta {
                HStack(spacing: 8) {
                    Image(systemName: meta.cached ? "bolt.fill" : "sparkles")
                        .foregroundStyle(meta.cached ? .yellow : .blue)
                    Text(
                        "\(meta.cached ? "Cached take" : "Fresh take") • \(TimeHelper.formatDuration(meta.durationSeconds))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }

            if !takes.isEmpty {
                takePicker
            }

            if meta != nil, scope.isFullDialog {
                HStack(spacing: 12) {
                    Button {
                        exportMono()
                    } label: {
                        Label("Export Mono WAV", systemImage: "waveform")
                    }
                    .disabled(isWorking)

                    Button {
                        exportMultichannel()
                    } label: {
                        Label("Export 17-Channel WAV", systemImage: "square.split.1x2")
                    }
                    .disabled(isWorking)

                    Button {
                        exportShareable()
                    } label: {
                        Label("Export Shareable MP3", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .onChange(of: turnContent) {
            // Takes are keyed by sha256(turns) server-side; a turn change means everything
            // shown here belongs to a different cache key now.
            meta = nil
            takes = []
            isWorking = false
            statusMessage = nil
            scopedGenerationId = nil
            requestToken = UUID()
            fullDialogMeta = nil
            selectedGenerationId = nil
            audioManager.stopURLPlayback()
            if scope.selectedTurns(from: turns) == nil {
                scope = .full
            }
        }
        .onChange(of: scope) {
            meta = scope.isFullDialog ? fullDialogMeta : nil
            takes = []
            isWorking = false
            statusMessage = nil
            scopedGenerationId = nil
            requestToken = UUID()
        }
        .errorAlert($errorAlert)
        .task(id: preferredGenerationId) {
            await restoreLatestCachedTakeIfAvailable()
        }
        .fileExporter(
            isPresented: $showExporter,
            document: AudioFileDocument(data: exportData ?? Data()),
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                logger.info("exported WAV to \(url.path)")
                statusMessage = "Exported \(url.lastPathComponent)"
            case .failure(let error):
                presentError("Export failed: \(error.localizedDescription)")
            }
            exportData = nil
        }
    }

    private var previewScopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Preview scope", selection: previewScopeKind) {
                Text("Full dialog").tag("full")
                Text("One turn").tag("turn")
                Text("Turn range").tag("range")
            }
            .pickerStyle(.segmented)

            switch scope {
            case .full:
                EmptyView()
            case .turn:
                Picker("Turn", selection: selectedTurnIndex) {
                    ForEach(turns.indices, id: \.self) { turnIndex in
                        Text("Turn \(turnIndex + 1)").tag(turnIndex)
                    }
                }
            case .range(let range):
                HStack {
                    Picker("From", selection: rangeStart) {
                        ForEach(turns.indices, id: \.self) { turnIndex in
                            Text("Turn \(turnIndex + 1)").tag(turnIndex)
                        }
                    }
                    Picker("Through", selection: rangeEnd) {
                        ForEach(turns.indices, id: \.self) { turnIndex in
                            Text("Turn \(turnIndex + 1)").tag(turnIndex)
                        }
                    }
                }
                .onAppear {
                    if range.upperBound >= turns.count {
                        scope = .range(range.lowerBound...max(range.lowerBound, turns.count - 1))
                    }
                }
            }
        }
    }

    private var previewScopeKind: Binding<String> {
        Binding(
            get: {
                switch scope {
                case .full: "full"
                case .turn: "turn"
                case .range: "range"
                }
            },
            set: { value in
                switch value {
                case "turn": scope = .turn(0)
                case "range": scope = .range(0...max(0, min(1, turns.count - 1)))
                default: scope = .full
                }
            })
    }

    private var selectedTurnIndex: Binding<Int> {
        Binding(
            get: {
                guard case .turn(let index) = scope else { return 0 }
                return min(index, max(0, turns.count - 1))
            },
            set: { scope = .turn($0) })
    }

    private var rangeStart: Binding<Int> {
        Binding(
            get: {
                guard case .range(let range) = scope else { return 0 }
                return range.lowerBound
            },
            set: { newStart in
                guard case .range(let range) = scope else { return }
                scope = .range(newStart...max(newStart, range.upperBound))
            })
    }

    private var rangeEnd: Binding<Int> {
        Binding(
            get: {
                guard case .range(let range) = scope else { return 0 }
                return range.upperBound
            },
            set: { newEnd in
                guard case .range(let range) = scope else { return }
                scope = .range(min(range.lowerBound, newEnd)...newEnd)
            })
    }

    private var takePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Available takes (newest first)").font(.caption).foregroundStyle(.secondary)
            Picker("Take", selection: activeGenerationId) {
                ForEach(Array(takes.enumerated()), id: \.element.id) { index, take in
                    Text(takeLabel(take, index: index))
                        .tag(Optional(take.generationId))
                }
            }
            .labelsHidden()
            .onChange(of: activeGenerationId.wrappedValue) { _, newValue in
                // Re-audition the newly chosen take. Skip when the selection was cleared
                // (turns changed) or when it's the take we're already showing (preview()
                // writes the id back after each request).
                guard let newValue, newValue != meta?.generationId, turnsAreReady, !isWorking else {
                    return
                }
                loadCachedTake(newValue)
            }
        }
    }

    private var activeGenerationId: Binding<DialogGenerationIdentifier?> {
        scope.isFullDialog ? $selectedGenerationId : $scopedGenerationId
    }

    // MARK: - Actions

    private func loadCachedTake(_ generationId: DialogGenerationIdentifier) {
        guard !isWorking, meta?.generationId != generationId, turnsAreReady else { return }
        activeGenerationId.wrappedValue = generationId
        preview(regenerate: false)
    }

    private func restoreLatestCachedTakeIfAvailable() async {
        guard restoreCachedTake, scope.isFullDialog, fullDialogMeta == nil, turnsAreReady else {
            return
        }
        let token = requestToken
        // Prevent the picker binding from starting a second preview while restoration selects a
        // take below.
        isWorking = true

        let request = DialogPreviewRequest.fromTurns(previewTurns, title: title)
        switch await server.dialogPreviewLookup(request) {
        case .failure(.notFound):
            guard token == requestToken else { return }
            if let preferredGenerationId {
                takes = [existingRenderedTake(preferredGenerationId)]
                selectedGenerationId = preferredGenerationId
                isWorking = false
                statusMessage =
                    "Using the voice take from the existing render. Preview audio is no longer cached."
            } else {
                takes = []
                isWorking = false
                statusMessage = "No cached takes yet — Preview to generate one."
            }
        case .failure(let error):
            guard token == requestToken else { return }
            isWorking = false
            statusMessage = "Could not restore cached takes: \(error.localizedDescription)"
        case .success(let lookup):
            guard !lookup.generations.isEmpty, token == requestToken else {
                isWorking = false
                return
            }

            takes = lookup.generations
            let availableGenerationIDs = Set(lookup.generations.map(\.generationId))
            if let preferredGenerationId {
                if availableGenerationIDs.contains(preferredGenerationId) {
                    selectedGenerationId = preferredGenerationId
                    statusMessage = "Restoring the voice take from the existing render…"
                } else {
                    // Render provenance can outlive the server's temporary preview cache. Keep
                    // the actual rendered voice visible and selected instead of silently
                    // switching the author to an unrelated newer take.
                    takes.append(existingRenderedTake(preferredGenerationId))
                    selectedGenerationId = preferredGenerationId
                    isWorking = false
                    statusMessage =
                        "Using the voice take from the existing render. Preview audio is no longer cached."
                    return
                }
            } else {
                selectedGenerationId = lookup.latestGenerationId
                statusMessage = "Restoring the latest cached voice take…"
            }
            preview(regenerate: false, play: false)
        }
    }

    private func existingRenderedTake(
        _ generationId: DialogGenerationIdentifier
    ) -> DialogPreviewLookupDTO.Generation {
        DialogPreviewLookupDTO.Generation(generationId: generationId, createdAt: "")
    }

    /// Resolve preview meta, transparently riding the generation job when the server
    /// queues one (fresh takes / long scenes). Cache hits return immediately; queued
    /// generations publish progress into `statusMessage` and resolve from the job's
    /// completion result.
    private func resolveMeta(_ request: DialogPreviewRequest, token: UUID? = nil) async -> Result<
        DialogPreviewMetaDTO, ServerError
    > {
        switch await server.dialogPreviewMeta(request) {
        case .failure(let error):
            return .failure(error)
        case .success(.meta(let dto)):
            return .success(dto)
        case .success(.queued(let job)):
            await JobStatusStore.shared.seedQueued(job)
            for await event in await JobStatusStore.shared.events(forJob: job.jobId) {
                switch event {
                case .updated(let info):
                    let percent = Int((info.progress ?? 0) * 100)
                    if token == nil || token == requestToken {
                        statusMessage = "Generating voices… \(percent)%"
                    }
                case .terminal(let info):
                    guard info.status == .completed else {
                        return .failure(
                            .serverError(
                                info.result ?? "The preview generation failed on the server."))
                    }
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    guard let result = info.result, let data = result.data(using: .utf8),
                        let dto = try? decoder.decode(DialogPreviewMetaDTO.self, from: data)
                    else {
                        return .failure(
                            .dataFormatError(
                                "The preview job finished but its result could not be decoded."))
                    }
                    return .success(dto)
                case .removed:
                    return .failure(
                        .serverError("The preview job was removed before it finished."))
                }
            }
            return .failure(.serverError("The preview job stream ended unexpectedly."))
        }
    }

    private func preview(regenerate: Bool, play: Bool = true) {
        guard turnsAreReady else { return }
        isWorking = true
        statusMessage = regenerate ? "Generating a fresh take…" : "Preparing preview…"
        let request = DialogPreviewRequest.fromTurns(
            previewTurns,
            generationId: regenerate ? nil : activeGenerationId.wrappedValue,
            regenerate: regenerate ? true : nil,
            title: title)
        let token = UUID()
        requestToken = token
        Task {
            let result = await resolveMeta(request, token: token)
            guard token == requestToken else { return }
            switch result {
            case .success(let dto):
                meta = dto
                activeGenerationId.wrappedValue = dto.generationId
                if scope.isFullDialog {
                    fullDialogMeta = dto
                }
                if play {
                    await playMeta(dto, token: token)
                } else {
                    isWorking = false
                    statusMessage = "Latest cached voice take loaded"
                }
            case .failure(let error):
                isWorking = false
                statusMessage = nil
                presentError(ServerError.detailedMessage(from: error))
            }
        }
    }

    private func playMeta(_ dto: DialogPreviewMetaDTO, token: UUID) async {
        guard token == requestToken else { return }
        guard
            case .success(let url) = server.dialogPreviewRenditionURL(
                cacheKey: dto.cacheKey, generationId: dto.generationId, as: .mp3)
        else {
            isWorking = false
            presentError("Could not build the preview MP3 URL.")
            return
        }
        // The server's preview audio URL is a WAV intended for rendering. Client playback uses
        // the smaller MP3 rendition instead, downloaded with the configured request headers and
        // cached locally before handing it to AVFoundation.
        let result = await server.downloadRawData(from: url)
        guard token == requestToken else { return }
        isWorking = false
        switch result {
        case .success(let data):
            switch audioManager.cacheAudioData(
                data,
                cacheKey: "preview-\(dto.cacheKey)-\(dto.generationId.uuidString.lowercased())",
                fileExtension: "mp3")
            {
            case .success(let localURL):
                statusMessage = "Playing preview…"
                if case .failure(let audioError) = audioManager.playURL(localURL) {
                    presentError("Playback failed: \(audioError.localizedDescription)")
                }
            case .failure(let audioError):
                presentError("Could not cache preview audio: \(audioError.localizedDescription)")
            }
        case .failure(let error):
            presentError("Could not load preview MP3: \(ServerError.detailedMessage(from: error))")
        }
    }

    private func refreshTakes() {
        guard turnsAreReady else { return }
        let token = UUID()
        requestToken = token
        isWorking = true
        statusMessage = "Looking up cached takes…"
        Task {
            let result = await server.dialogPreviewLookup(.fromTurns(previewTurns))
            guard token == requestToken else { return }
            isWorking = false
            switch result {
            case .success(let dto):
                takes = dto.generations
                let generationId = activeGenerationId.wrappedValue ?? dto.latestGenerationId
                activeGenerationId.wrappedValue = generationId
                statusMessage = "\(dto.generations.count) cached take(s)"
                isWorking = false
                loadCachedTake(generationId)
            case .failure(.notFound):
                takes = []
                statusMessage = "No cached takes yet — Preview to generate one."
            case .failure(let error):
                presentError(ServerError.detailedMessage(from: error))
            }
        }
    }

    private func exportMono() {
        // Ensure we have meta (and therefore an audio URL) for the current selection.
        let token = UUID()
        requestToken = token
        isWorking = true
        statusMessage = "Fetching mono WAV…"
        let request = DialogPreviewRequest.fromTurns(
            previewTurns, generationId: activeGenerationId.wrappedValue, title: title)
        Task {
            let metaResult = await resolveMeta(request, token: token)
            guard token == requestToken else { return }
            guard case .success(let dto) = metaResult,
                let url = server.makeAbsoluteURL(fromRelativePath: dto.audioUrl)
            else {
                isWorking = false
                presentError("Could not resolve the mono audio for export.")
                return
            }
            let dataResult = await server.downloadRawData(from: url)
            guard token == requestToken else { return }
            isWorking = false
            switch dataResult {
            case .success(let data):
                exportData = data
                exportFilename = "dialog-mono-\(dto.generationId.uuidString.lowercased()).wav"
                exportContentType = .wav
                showExporter = true
            case .failure(let error):
                presentError(ServerError.detailedMessage(from: error))
            }
        }
    }

    private func exportShareable() {
        // Resolve meta for the current selection so we have the cache key + take id, then let the
        // server encode that take's cached PCM to MP3 (the GUI's share format — plays in Slack and
        // AVFoundation, unlike the Ogg the CLI still offers).
        let token = UUID()
        requestToken = token
        isWorking = true
        statusMessage = "Encoding shareable MP3…"
        let request = DialogPreviewRequest.fromTurns(
            previewTurns, generationId: activeGenerationId.wrappedValue, title: title)
        Task {
            let metaResult = await resolveMeta(request, token: token)
            guard token == requestToken else { return }
            guard case .success(let dto) = metaResult,
                case .success(let url) = server.dialogPreviewRenditionURL(
                    cacheKey: dto.cacheKey, generationId: dto.generationId, as: .mp3)
            else {
                isWorking = false
                presentError("Could not resolve the shareable audio for export.")
                return
            }
            let dataResult = await server.downloadRawData(from: url)
            guard token == requestToken else { return }
            isWorking = false
            switch dataResult {
            case .success(let data):
                exportData = data
                exportFilename =
                    "dialog-preview-\(dto.generationId.uuidString.lowercased().prefix(8)).mp3"
                exportContentType = .mp3
                showExporter = true
                statusMessage = "Ready to save shareable MP3"
            case .failure(let error):
                presentError(ServerError.detailedMessage(from: error))
            }
        }
    }

    private func exportMultichannel() {
        let token = UUID()
        requestToken = token
        isWorking = true
        statusMessage = "Rendering 17-channel WAV…"
        let request = DialogPreviewRequest.fromTurns(
            previewTurns, generationId: activeGenerationId.wrappedValue, title: title)
        Task {
            // Always a job now (server 3.23.0) — long scenes make enormous WAVs. Watch
            // it, then download the assembled file from the ad-hoc sound bucket.
            switch await server.dialogPreviewMultichannel(request) {
            case .failure(let error):
                guard token == requestToken else { return }
                isWorking = false
                presentError(ServerError.detailedMessage(from: error))
            case .success(let job):
                await JobStatusStore.shared.seedQueued(job)
                for await event in await JobStatusStore.shared.events(forJob: job.jobId) {
                    guard token == requestToken else { return }
                    switch event {
                    case .updated(let info):
                        let percent = Int((info.progress ?? 0) * 100)
                        statusMessage = "Rendering 17-channel WAV… \(percent)%"
                    case .terminal(let info):
                        await finishMultichannelExport(info, token: token)
                    case .removed:
                        isWorking = false
                        presentError("The export job was removed before it finished.")
                    }
                }
            }
        }
    }

    private func finishMultichannelExport(_ info: JobStatusStore.JobInfo, token: UUID) async {
        guard token == requestToken else { return }
        guard info.status == .completed,
            let result = info.result, let data = result.data(using: .utf8),
            let export = try? JSONDecoder().decode(DialogPreviewExportResult.self, from: data)
        else {
            isWorking = false
            presentError(
                info.status == .completed
                    ? "The export finished but its result could not be decoded."
                    : (info.result ?? "The 17-channel export failed on the server."))
            return
        }
        guard case .success(let url) = server.getAdHocSoundURL(export.fileName) else {
            isWorking = false
            presentError("Could not build the download URL for the exported WAV.")
            return
        }
        let dataResult = await server.downloadRawData(from: url)
        guard token == requestToken else { return }
        isWorking = false
        switch dataResult {
        case .success(let wavData):
            exportData = wavData
            exportFilename = export.fileName
            exportContentType = .wav
            showExporter = true
            statusMessage = "Ready to save 17-channel WAV"
        case .failure(let error):
            presentError(ServerError.detailedMessage(from: error))
        }
    }

    private func presentError(_ message: String) {
        errorAlert = ErrorAlert(title: "Preview Error", message: message)
        statusMessage = nil
    }

    private func takeLabel(_ take: DialogPreviewLookupDTO.Generation, index: Int) -> String {
        if take.generationId == preferredGenerationId, take.createdAt.isEmpty {
            return "#\(index + 1) • Existing rendered voice"
        }
        let shortId = String(take.generationId.uuidString.lowercased().prefix(8))
        if let date = take.createdAtDate {
            return "#\(index + 1) • \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "#\(index + 1) • \(shortId)"
    }
}

private struct DialogMusicCandidate: Identifiable, Equatable {
    let result: DialogMusicGenerationResult
    let sourceCacheKey: String
    let sourceDialogGenerationId: DialogGenerationIdentifier
    let sourceScriptUpdatedAt: Int64?
    var isExpired = false

    var id: UUID { result.musicGenerationId }

    func matches(_ meta: DialogPreviewMetaDTO?, scriptUpdatedAt: Int64?) -> Bool {
        sourceCacheKey == meta?.cacheKey
            && sourceDialogGenerationId == meta?.generationId
            && sourceScriptUpdatedAt == scriptUpdatedAt
    }
}

/// Music is deliberately downstream of a saved, full-dialog voice take. Keeping candidates in
/// session state makes experimentation cheap while promotion remains an explicit commit point.
struct DialogMusicPanel: View {
    let scriptId: DialogScriptIdentifier?
    let fullDialogMeta: DialogPreviewMetaDTO?
    let backgroundMusic: DialogBackgroundMusic?
    let scriptUpdatedAt: Int64?
    let hasUnsavedChanges: Bool
    let onScriptUpdated: (DialogScript) -> Void
    let onMusicUpdated: (DialogBackgroundMusic?) -> Void

    private let server = CreatureServerClient.shared
    private let audioManager = AudioManager.shared

    @State private var prompt = ""
    @State private var generationMode: DialogMusicGenerationMode = .track
    @State private var durationExtensionSeconds = 0.0
    @State private var candidates: [DialogMusicCandidate] = []
    @State private var activeJobId: String?
    @State private var observedJob: JobStatusStore.JobInfo?
    @State private var jobSourceMeta: DialogPreviewMetaDTO?
    @State private var jobSourceScriptUpdatedAt: Int64?
    @State private var isSubmitting = false
    @State private var isAuditioning = false
    @State private var musicVolume = 0.35
    @State private var candidateToPromote: DialogMusicCandidate?
    @State private var showReplacementConfirmation = false
    @State private var showClearConfirmation = false
    @State private var soundToShare: String?
    @State private var statusMessage: String?
    @State private var errorAlert: ErrorAlert?
    @State private var auditionToken = UUID()
    @State private var musicPlaybackToken = UUID()
    @State private var isPlayingAcceptedMusic = false

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        scriptId != nil && fullDialogMeta != nil && !hasUnsavedChanges && !trimmedPrompt.isEmpty
            && trimmedPrompt.utf8.count <= DialogLimits.maxMusicPromptBytes
            && !isSubmitting && !(observedJob.map { !$0.isTerminal } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("3. Background Music").font(.title2.bold())
                Spacer()
                if isSubmitting || (observedJob.map { !$0.isTerminal } ?? false) {
                    ProgressView().controlSize(.small)
                }
            }

            if let backgroundMusic {
                acceptedMusicCard(backgroundMusic)
            }

            TextField(
                "Describe the score, mood, instruments, and pacing…", text: $prompt,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
            HStack {
                Spacer()
                Text("\(trimmedPrompt.utf8.count)/\(DialogLimits.maxMusicPromptBytes) bytes")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(
                        trimmedPrompt.utf8.count > DialogLimits.maxMusicPromptBytes
                            ? .red : .secondary)
            }

            Picker("Generation style", selection: $generationMode) {
                ForEach(DialogMusicGenerationMode.allCases, id: \.self) { mode in
                    Text(modeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Music after dialog")
                    Spacer()
                    Text("\(Int(durationExtensionSeconds)) seconds")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $durationExtensionSeconds, in: 0...60, step: 1)
                Text(
                    "The final show lasts for whichever is longer: the dialog or accepted music. The dialog channels remain neutral during a music-only tail."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let reason = unavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    generate()
                } label: {
                    Label("Generate Candidate", systemImage: "music.note.list")
                }
                .buttonStyle(.glassProminent)
                .disabled(!canGenerate)

                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Candidates").font(.headline)
                    ForEach(candidates) { candidate in
                        candidateCard(candidate)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Music level", systemImage: "speaker.wave.2")
                    Slider(value: $musicVolume, in: 0...1)
                    Text("\(Int(musicVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }
                Text(
                    "This affects audition playback only; rendered channel 17 is not remixed here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .watchJob(activeJobId) { info in
            observedJob = info
            let percent = Int((info.progress ?? 0) * 100)
            statusMessage = "Generating music… \(percent)%"
        } onTerminal: { info in
            observedJob = info
            finishGeneration(info)
        } onRemoved: {
            activeJobId = nil
            statusMessage = nil
        }
        .onChange(of: musicVolume) { _, value in
            audioManager.dialogMusicVolume = Float(value)
        }
        .onChange(of: fullDialogMeta) { _, _ in
            auditionToken = UUID()
            isAuditioning = false
            audioManager.stopDialogAudition()
        }
        .onChange(of: scriptUpdatedAt) { _, _ in
            auditionToken = UUID()
            isAuditioning = false
            audioManager.stopDialogAudition()
        }
        .onDisappear {
            auditionToken = UUID()
            musicPlaybackToken = UUID()
            isAuditioning = false
            isPlayingAcceptedMusic = false
            audioManager.stopDialogAudition()
            audioManager.stopURLPlayback()
        }
        .shareableSoundFlow(fileName: $soundToShare)
        .errorAlert($errorAlert)
        .confirmationDialog(
            "Replace accepted background music?", isPresented: $showReplacementConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Music", role: .destructive) {
                if let candidateToPromote { promote(candidateToPromote) }
            }
            Button("Cancel", role: .cancel) { candidateToPromote = nil }
        } message: {
            Text("The newly accepted candidate will be used by future final renders.")
        }
        .confirmationDialog(
            "Remove accepted background music?", isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Music", role: .destructive) { clearAcceptedMusic() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Future renders will contain dialog only. The generated sound file will be retained."
            )
        }
    }

    private var unavailableReason: String? {
        if scriptId == nil || hasUnsavedChanges {
            return "Save the current script before generating music."
        }
        if fullDialogMeta == nil {
            return
                "Generate and select a full-dialog voice take first. Partial previews cannot drive music generation."
        }
        return nil
    }

    @ViewBuilder
    private func acceptedMusicCard(_ music: DialogBackgroundMusic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accepted music", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.headline)
            Text(music.prompt).font(.subheadline)
            Text(music.soundFile)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Play with Dialog") { auditionAccepted(music) }
                    .disabled(fullDialogMeta == nil || isAuditioning)
                Button(isPlayingAcceptedMusic ? "Stop Music" : "Play Music") {
                    if isPlayingAcceptedMusic {
                        stopAcceptedMusic()
                    } else {
                        playAcceptedMusic(music)
                    }
                }
                .disabled(isAuditioning)
                Button("Share MP3…") { soundToShare = music.soundFile }
            }
            Button("Remove Accepted Music", role: .destructive) {
                showClearConfirmation = true
            }
            .buttonStyle(.borderless)
            .disabled(scriptId == nil || hasUnsavedChanges)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular.tint(.green.opacity(0.18)), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func candidateCard(_ candidate: DialogMusicCandidate) -> some View {
        let isCurrent = candidate.matches(fullDialogMeta, scriptUpdatedAt: scriptUpdatedAt)
        let isAccepted = backgroundMusic?.generationId == candidate.id
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(candidate.result.prompt).font(.subheadline.bold())
                Spacer()
                Text(TimeHelper.formatDuration(candidate.result.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(
                "Requested \(TimeHelper.formatDuration(Double(candidate.result.requestedMusicLengthMilliseconds) / 1_000)) • final show \(TimeHelper.formatDuration(candidate.result.finalShowDurationSeconds))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if candidate.isExpired {
                Label(
                    "This temporary candidate expired. Generate it again.",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else if !isCurrent {
                Label(
                    "This candidate belongs to an older voice take.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            HStack {
                Button("Play with Dialog") { audition(candidate) }
                    .disabled(candidate.isExpired || !isCurrent || isAuditioning)
                if isAccepted {
                    Label("Accepted for Final Render", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(
                        backgroundMusic == nil
                            ? "Accept for Final Render" : "Replace Accepted Music"
                    ) { requestPromotion(candidate) }
                    .buttonStyle(.glassProminent)
                    .disabled(candidate.isExpired || !isCurrent || hasUnsavedChanges)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    private func generate() {
        guard let scriptId, let meta = fullDialogMeta, canGenerate else { return }
        isSubmitting = true
        jobSourceMeta = meta
        jobSourceScriptUpdatedAt = scriptUpdatedAt
        statusMessage = "Starting music generation…"
        let request = DialogMusicRequest(
            scriptId: scriptId,
            dialogCacheKey: meta.cacheKey,
            dialogGenerationId: meta.generationId,
            prompt: trimmedPrompt,
            durationExtensionMilliseconds: Int64(durationExtensionSeconds * 1_000),
            generationMode: generationMode)
        Task {
            let result = await server.generateDialogMusic(request)
            await MainActor.run {
                isSubmitting = false
                switch result {
                case .success(let job):
                    Task { await JobStatusStore.shared.seedQueued(job) }
                    activeJobId = job.jobId
                case .failure(let error):
                    presentError("Music Generation Failed", error)
                }
            }
        }
    }

    private func finishGeneration(_ info: JobStatusStore.JobInfo) {
        defer { activeJobId = nil }
        guard info.status == .completed, let result = info.dialogMusicResult,
            let sourceMeta = jobSourceMeta
        else {
            errorAlert = ErrorAlert(
                title: "Music Generation Failed",
                message: info.result ?? "The server did not return a music candidate.")
            statusMessage = nil
            return
        }
        let candidate = DialogMusicCandidate(
            result: result, sourceCacheKey: sourceMeta.cacheKey,
            sourceDialogGenerationId: sourceMeta.generationId,
            sourceScriptUpdatedAt: jobSourceScriptUpdatedAt)
        candidates.insert(candidate, at: 0)
        statusMessage = "Candidate ready"
        audition(candidate)
    }

    private func requestPromotion(_ candidate: DialogMusicCandidate) {
        candidateToPromote = candidate
        if backgroundMusic == nil {
            promote(candidate)
        } else {
            showReplacementConfirmation = true
        }
    }

    private func promote(_ candidate: DialogMusicCandidate) {
        guard !hasUnsavedChanges,
            candidate.matches(fullDialogMeta, scriptUpdatedAt: scriptUpdatedAt)
        else { return }
        let promotionScriptId = scriptId
        let promotionMeta = fullDialogMeta
        let promotionUpdatedAt = scriptUpdatedAt
        statusMessage = "Accepting music…"
        Task {
            switch await server.promoteDialogMusic(generationId: candidate.id) {
            case .success(let result):
                let accepted = DialogBackgroundMusic(
                    soundFile: result.soundFile,
                    generationId: result.musicGenerationId,
                    prompt: candidate.result.prompt,
                    acceptedAt: Int64(Date().timeIntervalSince1970 * 1_000))
                if let scriptId {
                    switch await server.getDialogScript(id: scriptId) {
                    case .success(let canonical):
                        await MainActor.run {
                            guard scriptId == promotionScriptId,
                                fullDialogMeta == promotionMeta,
                                scriptUpdatedAt == promotionUpdatedAt,
                                !hasUnsavedChanges
                            else {
                                return
                            }
                            onScriptUpdated(canonical)
                            candidateToPromote = nil
                            statusMessage = "Music accepted for final render"
                        }
                    case .failure(let error):
                        await MainActor.run {
                            guard scriptId == promotionScriptId,
                                fullDialogMeta == promotionMeta,
                                scriptUpdatedAt == promotionUpdatedAt,
                                !hasUnsavedChanges
                            else {
                                return
                            }
                            // Promotion succeeded; retain that local state, but make the
                            // follow-up canonical-read failure visible instead of pretending
                            // the script revision is known.
                            onMusicUpdated(accepted)
                            candidateToPromote = nil
                            presentError(
                                "Music Accepted, But Script Refresh Failed", error)
                        }
                    }
                } else {
                    await MainActor.run {
                        guard scriptId == promotionScriptId,
                            fullDialogMeta == promotionMeta,
                            scriptUpdatedAt == promotionUpdatedAt,
                            !hasUnsavedChanges
                        else {
                            return
                        }
                        onMusicUpdated(accepted)
                        candidateToPromote = nil
                        statusMessage = "Music accepted for final render"
                    }
                }
            case .failure(let error):
                await MainActor.run { presentError("Could Not Accept Music", error) }
            }
        }
    }

    private func clearAcceptedMusic() {
        guard let scriptId else { return }
        let clearScriptId = scriptId
        statusMessage = "Removing accepted music…"
        Task {
            switch await server.clearDialogMusic(scriptId: scriptId) {
            case .success(let canonical):
                await MainActor.run {
                    guard self.scriptId == clearScriptId, !hasUnsavedChanges else { return }
                    onScriptUpdated(canonical)
                    statusMessage = "Accepted music removed"
                }
            case .failure(let error):
                await MainActor.run { presentError("Could Not Remove Music", error) }
            }
        }
    }

    private func audition(_ candidate: DialogMusicCandidate) {
        guard let meta = fullDialogMeta,
            let musicURL = server.makeAbsoluteURL(fromRelativePath: candidate.result.mp3Url)
        else { return }
        audition(meta: meta, musicURL: musicURL, candidateId: candidate.id)
    }

    private func auditionAccepted(_ music: DialogBackgroundMusic) {
        guard let meta = fullDialogMeta,
            case .success(let musicURL) = server.getSoundRenditionURL(music.soundFile, as: .mp3)
        else { return }
        audition(meta: meta, musicURL: musicURL, candidateId: nil)
    }

    private func playAcceptedMusic(_ music: DialogBackgroundMusic) {
        let renditionResult = server.getSoundRenditionURL(music.soundFile, as: .mp3)
        guard case .success(let musicURL) = renditionResult else {
            if case .failure(let error) = renditionResult {
                presentError("Music Playback Failed", error)
            }
            return
        }
        let token = UUID()
        musicPlaybackToken = token
        statusMessage = "Preparing accepted music…"
        Task {
            let result = await server.downloadRawData(from: musicURL)
            await MainActor.run {
                guard token == musicPlaybackToken else { return }
                switch result {
                case .success(let data):
                    switch audioManager.cacheAudioData(
                        data,
                        cacheKey: "accepted-music-(music.generationId.uuidString.lowercased())",
                        fileExtension: "mp3")
                    {
                    case .success(let localURL):
                        if case .failure(let error) = audioManager.playURL(localURL) {
                            errorAlert = ErrorAlert(
                                title: "Music Playback Failed",
                                message: error.localizedDescription)
                        } else {
                            isPlayingAcceptedMusic = true
                            statusMessage = "Playing accepted music"
                        }
                    case .failure(let error):
                        errorAlert = ErrorAlert(
                            title: "Music Playback Failed", message: error.localizedDescription)
                    }
                case .failure(let error):
                    presentError("Music Playback Failed", error)
                }
            }
        }
    }

    private func stopAcceptedMusic() {
        musicPlaybackToken = UUID()
        isPlayingAcceptedMusic = false
        audioManager.stopURLPlayback()
        statusMessage = nil
    }

    private func audition(
        meta: DialogPreviewMetaDTO, musicURL: URL, candidateId: UUID?
    ) {
        guard
            case .success(let voiceURL) = server.dialogPreviewRenditionURL(
                cacheKey: meta.cacheKey, generationId: meta.generationId, as: .mp3)
        else {
            errorAlert = ErrorAlert(
                title: "Audition Failed", message: "Could not build the dialog MP3 URL.")
            return
        }
        let token = UUID()
        auditionToken = token
        isAuditioning = true
        statusMessage = "Preparing dialog and music…"
        Task {
            async let voiceDownload = server.downloadRawData(from: voiceURL)
            let musicDownload = await server.downloadRawData(from: musicURL)
            let voiceResult = await voiceDownload
            await MainActor.run {
                guard token == auditionToken else { return }
                isAuditioning = false
                switch voiceResult {
                case .success(let voiceData):
                    switch audioManager.cacheAudioData(
                        voiceData,
                        cacheKey:
                            "preview-\(meta.cacheKey)-\(meta.generationId.uuidString.lowercased())",
                        fileExtension: "mp3")
                    {
                    case .success(let localVoiceURL):
                        switch musicDownload {
                        case .success(let data):
                            switch audioManager.cacheAudioData(
                                data,
                                cacheKey: candidateId?.uuidString.lowercased()
                                    ?? "accepted-\(meta.cacheKey)",
                                fileExtension: "mp3")
                            {
                            case .success(let localMusicURL):
                                if case .failure(let error) = audioManager.playDialogAudition(
                                    voiceURL: localVoiceURL, musicURL: localMusicURL,
                                    musicVolume: Float(musicVolume))
                                {
                                    errorAlert = ErrorAlert(
                                        title: "Audition Failed",
                                        message: error.localizedDescription)
                                } else {
                                    statusMessage = "Playing dialog with music"
                                }
                            case .failure(let error):
                                errorAlert = ErrorAlert(
                                    title: "Audition Failed", message: error.localizedDescription)
                            }
                        case .failure(.notFound):
                            if let candidateId,
                                let index = candidates.firstIndex(where: { $0.id == candidateId })
                            {
                                candidates[index].isExpired = true
                            }
                            statusMessage = nil
                        case .failure(let error):
                            presentError("Audition Failed", error)
                        }
                    case .failure(let error):
                        errorAlert = ErrorAlert(
                            title: "Audition Failed", message: error.localizedDescription)
                    }
                case .failure(let error):
                    errorAlert = ErrorAlert(
                        title: "Audition Failed",
                        message: ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func modeLabel(_ mode: DialogMusicGenerationMode) -> String {
        switch mode {
        case .track: "Track"
        case .loop: "Loop"
        case .ambience: "Ambience"
        }
    }

    private func presentError(_ title: String, _ error: ServerError) {
        errorAlert = ErrorAlert(title: title, message: ServerError.detailedMessage(from: error))
        statusMessage = nil
        activeJobId = nil
        isSubmitting = false
    }
}
