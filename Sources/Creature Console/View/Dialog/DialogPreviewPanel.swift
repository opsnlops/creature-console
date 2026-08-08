import AVFoundation
import Common
import Foundation
import OSLog
import SwiftData
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
    /// sha256(turns) as the server computes it, learned from the takes lookup. The render gate's
    /// freshness comparison (accepted take vs current turns) reads this.
    @Binding var currentCacheKey: String?
    /// Saved-script identity, required to Accept. Nil (unsaved) leaves Accept disabled.
    var scriptId: DialogScriptIdentifier? = nil
    /// The script's accepted voice, from the saved copy.
    var acceptedVoice: DialogAcceptedVoice? = nil
    /// Whether this script already has rendered animations, so the empty takes list can say
    /// "your renders are fine, their takes just aged out" instead of implying a virgin script.
    var hasExistingRender: Bool = false
    /// The script's stage binding, for spatial audition — takes play positioned where the birds
    /// will actually sit.
    var stageId: StageIdentifier? = nil
    /// Canonical script handed back by accept/clear, for the editor to merge (music-flow shape).
    var onVoiceChanged: ((DialogScript) -> Void)? = nil

    private let server = CreatureServerClient.shared
    private let audioManager = AudioManager.shared

    @State private var isWorking = false
    @State private var statusMessage: String? = nil
    @State private var meta: DialogPreviewMetaDTO? = nil
    @State private var takes: [DialogPreviewLookupDTO.Generation] = []
    @State private var isAccepting = false

    #if os(macOS)
        /// Deliberately @AppStorage, deliberately not on the script: whether spatial audition
        /// sounds good is a property of the *machine's* audio hardware (April's laptop: great;
        /// the workshop Mac on plain speakers: not), so the preference must never sync between
        /// devices or ride the script.
        @AppStorage("voiceTakeSpatialAudition") private var spatialAudition = false
        @State private var spatialPlayer = SpatialAuditionPlayer()
    #endif
    @Query private var stageModels: [StageModel]

    /// The bound stage, resolved from the invalidation-fed mirror.
    private var spatialStage: Stage? {
        guard let stageId else { return nil }
        return stageModels.first(where: { $0.id == stageId })?.toDTO()
    }
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

            #if os(macOS)
                Toggle(isOn: $spatialAudition) {
                    Label("Spatial audition", systemImage: "spatial.audio")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(spatialStage == nil)
                .help(
                    spatialStage == nil
                        ? "Bind a stage to hear takes positioned in space."
                        : "Play takes through the stage's placements — the same render path as the Spatial Stage monitor. A per-machine setting: great on headphones, less so on plain speakers."
                )
                .onChange(of: spatialAudition) { _, _ in
                    spatialPlayer.stop()
                    audioManager.stopURLPlayback()
                }
            #endif

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

            if scope.isFullDialog {
                acceptedVoiceCard
            }

            // One generation verb: every press makes a *new* take and adds it to the list.
            // Auditioning is tapping a take; choosing is Accept. (April: "All should
            // regenerate, but only one can be chosen.")
            HStack(spacing: 12) {
                Button {
                    generateTake()
                } label: {
                    Label("Generate Take", systemImage: "sparkles")
                }
                .buttonStyle(.glass)
                .disabled(!turnsAreReady || isWorking)

                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            if !takes.isEmpty {
                takeList
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
            // Takes are keyed by sha256(turns) server-side; a turn change means everything shown
            // here belongs to a different cache key now. The acceptance itself is NOT touched —
            // it lives on the script and simply reads as stale until these turns are saved and
            // re-accepted. Nothing chosen is ever silently un-chosen.
            // Capture BEFORE clearing: these run on every keystroke in a turn's text field, and
            // AVFoundation teardown isn't free — only touch the audio stack when something was
            // actually loaded or playing.
            let hadAudio = meta != nil || isWorking
            meta = nil
            takes = []
            isWorking = false
            statusMessage = nil
            requestToken = UUID()
            fullDialogMeta = nil
            currentCacheKey = nil
            if hadAudio {
                audioManager.stopURLPlayback()
            }
            #if os(macOS)
                if spatialPlayer.isPlaying {
                    spatialPlayer.stop()
                }
            #endif
            if scope.selectedTurns(from: turns) == nil {
                scope = .full
            }
        }
        .onChange(of: scope) {
            meta = scope.isFullDialog ? fullDialogMeta : nil
            takes = []
            isWorking = false
            statusMessage = nil
            requestToken = UUID()
        }
        .errorAlert($errorAlert)
        // Listing takes is a free lookup (no generation), so the list is just *there* on open —
        // and it carries the cache key that resolves the acceptance's freshness immediately.
        //
        // Debounced: task(id:) restarts on every keystroke while turn text is edited, so
        // sleeping first means only a pause in typing reaches the server. Without this, each
        // keystroke fired a lookup POST and churned the panel's state — visible as typing lag.
        .task(id: turnContent) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await lookupTakes()
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

    /// The one voice this script will render with — or the reasons it can't render yet.
    @ViewBuilder
    private var acceptedVoiceCard: some View {
        if let acceptedVoice {
            let fresh = acceptedVoice.isFresh(forCacheKey: currentCacheKey)
            HStack(spacing: 8) {
                Image(systemName: fresh ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                    .foregroundStyle(fresh ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fresh ? "Accepted voice take" : "Accepted voice take is stale")
                        .font(.subheadline.bold())
                    Text(
                        fresh
                            ? "Accepted \(acceptedVoice.acceptedAtDate.formatted(date: .abbreviated, time: .shortened)) — this is the voice the render uses."
                            : "The turns changed since this take was accepted; its audio is of the old text. Generate, audition, and accept a new take."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if fresh {
                    Button("Play") {
                        // The promoted file is permanent; the preview-cache copy expires with
                        // the 24 h ad-hoc TTL. Prefer the one that always works.
                        if let soundFile = acceptedVoice.soundFile, !soundFile.isEmpty {
                            #if os(macOS)
                                if spatialAudition, let stage = spatialStage {
                                    playPromotedSpatially(soundFile, stage: stage)
                                    return
                                }
                            #endif
                            playPromoted(soundFile)
                        } else {
                            audition(generationId: acceptedVoice.generationId)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isWorking)
                }
            }
            .padding(10)
            .glassEffect(
                .regular.tint(fresh ? .green.opacity(0.18) : .orange.opacity(0.18)),
                in: .rect(cornerRadius: 10)
            )
            .contextMenu {
                Button(role: .destructive) {
                    clearAcceptance()
                } label: {
                    Label("Un-accept Voice", systemImage: "xmark.seal")
                }
            }

            Button("Un-accept Voice…", role: .destructive) {
                clearAcceptance()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(isAccepting || scriptId == nil)
            .help(
                "Moves the take back to ad-hoc storage (kept 24 hours) and reopens the choice. Rendering blocks until a voice is accepted again."
            )
        } else {
            Label(
                "No voice accepted yet. Generate takes, audition them, and accept the best one — renders only use audited voices.",
                systemImage: "waveform.badge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var takeList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Takes (newest first) — tap to audition · unaccepted takes are kept 24 hours")
                .font(.caption).foregroundStyle(.secondary)

            // The reason Accept is disabled must be *visible*, not a hover tooltip on a grey
            // button — typing anywhere in the turns dirties the script, and April hit exactly
            // that: a take she'd just auditioned with Accept greyed and nothing saying why.
            if scope.isFullDialog {
                if scriptId == nil {
                    Label(
                        "Save the script to accept a take — acceptance is checked against the saved turns.",
                        systemImage: "square.and.arrow.down"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else if currentCacheKey == nil {
                    Label("Checking takes against the current turns…", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(takes.enumerated()), id: \.element.id) { index, take in
                takeRow(take, index: index)
            }
        }
    }

    private func takeRow(_ take: DialogPreviewLookupDTO.Generation, index: Int) -> some View {
        let isPlayingRow = meta?.generationId == take.generationId
        let isAccepted = acceptedVoice?.generationId == take.generationId
        return HStack(spacing: 10) {
            Button {
                audition(generationId: take.generationId)
            } label: {
                Label(
                    takeLabel(take, index: index),
                    systemImage: isPlayingRow ? "speaker.wave.2.fill" : "play.circle")
            }
            .buttonStyle(.borderless)
            .disabled(isWorking)

            Spacer()

            if isAccepted {
                Label("Accepted", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if scope.isFullDialog {
                Button("Accept") {
                    accept(take)
                }
                .buttonStyle(.borderless)
                .disabled(isAccepting || scriptId == nil || currentCacheKey == nil)
                .help(
                    scriptId == nil
                        ? "Save the script before accepting a voice take."
                        : "Make this the voice the render uses.")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    /// Free lookup of the cached takes for the current turns. Runs on open and after every
    /// generation — it's also what learns the cache key that resolves acceptance freshness.
    private func lookupTakes() async {
        guard turnsAreReady, scope.isFullDialog else { return }
        let token = requestToken
        switch await server.dialogPreviewLookup(.fromTurns(previewTurns)) {
        case .success(let dto):
            guard token == requestToken else { return }
            takes = dto.generations
            currentCacheKey = dto.cacheKey
            if statusMessage == nil {
                statusMessage = "\(dto.generations.count) take(s)"
            }
        case .failure(.notFound):
            guard token == requestToken else { return }
            takes = []
            // A script with living renders isn't a blank slate: its takes simply aged out of the
            // 24 h audition cache. The renders keep playing; only *changing* the voice needs a
            // new take — and re-rendering replaces the old performance, so say so here rather
            // than letting the generic copy imply nothing exists.
            statusMessage =
                hasExistingRender
                ? "This script's takes have expired from the audition cache — its rendered animations still play. Generate a new take only if you want to change the voice (re-rendering replaces the old performance)."
                : "No takes yet — Generate one to start auditioning."
        case .failure(let error):
            guard token == requestToken else { return }
            statusMessage = "Could not list takes: \(error.localizedDescription)"
        }
    }

    /// Always a *new* take — generation and audition are different verbs on purpose.
    private func generateTake() {
        loadTake(generationId: nil, regenerate: true)
    }

    /// Play an existing take. Never generates.
    private func audition(generationId: DialogGenerationIdentifier) {
        loadTake(generationId: generationId, regenerate: false)
    }

    private func loadTake(generationId: DialogGenerationIdentifier?, regenerate: Bool) {
        guard turnsAreReady else { return }
        isWorking = true
        statusMessage = regenerate ? "Generating a fresh take…" : "Loading take…"
        let request = DialogPreviewRequest.fromTurns(
            previewTurns,
            generationId: generationId,
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
                if scope.isFullDialog {
                    fullDialogMeta = dto
                    currentCacheKey = dto.cacheKey
                }
                if regenerate {
                    // Refresh the list so the new take shows as a row alongside the others —
                    // generate four, compare, accept the best.
                    await lookupTakes()
                }
                await playMeta(dto, token: token)
            case .failure(let error):
                isWorking = false
                statusMessage = nil
                presentError(ServerError.detailedMessage(from: error))
            }
        }
    }

    #if os(macOS)
        private func playPromotedSpatially(_ soundFile: String, stage: Stage) {
            audioManager.stopURLPlayback()
            statusMessage = "Playing accepted voice spatially…"
            Task {
                do {
                    try await spatialPlayer.play(soundFile: soundFile, stage: stage)
                } catch {
                    await MainActor.run {
                        statusMessage = "Spatial audio unavailable — playing flat."
                        playPromoted(soundFile)
                    }
                }
            }
        }
    #endif

    /// Play the accepted voice through its promoted, permanent sound file — the path that still
    /// works after the take candidates have aged out of the ad-hoc store.
    private func playPromoted(_ soundFile: String) {
        switch server.getSoundRenditionURL(soundFile, as: .mp3) {
        case .success(let url):
            statusMessage = "Playing accepted voice…"
            if case .failure(let error) = audioManager.playURL(url) {
                presentError("Playback failed: \(error.message)")
            }
        case .failure(let error):
            presentError(
                "Could not build the accepted voice URL: \(ServerError.detailedMessage(from: error))"
            )
        }
    }

    /// Un-accept: the server demotes the promoted file back to ad-hoc (24 h TTL restarts) and
    /// returns the canonical script with no acceptance. Rendering blocks until a new Accept.
    private func clearAcceptance() {
        guard let scriptId else { return }
        isAccepting = true
        statusMessage = "Un-accepting voice…"
        Task {
            let result = await server.clearDialogVoice(scriptId: scriptId)
            await MainActor.run {
                isAccepting = false
                switch result {
                case .success(let canonical):
                    statusMessage = "Voice un-accepted — the take is back in ad-hoc for 24 hours"
                    onVoiceChanged?(canonical)
                case .failure(let error):
                    statusMessage = nil
                    presentError(
                        ServerError.detailedMessage(from: error), title: "Un-accept Failed")
                }
            }
        }
    }

    /// Make this take the script's voice. Ordinarily immediate (200); when the take's audio has
    /// to be assembled first — pre-3.40.1 takes, or an ad-hoc file the sweep reclaimed — the
    /// server queues a job (202) whose completion result is the same canonical script, so both
    /// paths land in the same merge. Validation is synchronous either way: a stale cache key or
    /// unknown generation fails right here, never a minute later inside a job.
    private func accept(_ take: DialogPreviewLookupDTO.Generation) {
        guard let scriptId, let currentCacheKey else { return }
        isAccepting = true
        statusMessage = "Accepting take…"
        Task {
            let result = await server.acceptDialogVoice(
                scriptId: scriptId,
                generationId: take.generationId,
                dialogCacheKey: currentCacheKey)
            switch result {
            case .success(.accepted(let canonical)):
                await MainActor.run {
                    isAccepting = false
                    statusMessage = "Voice accepted"
                    onVoiceChanged?(canonical)
                }
            case .success(.queued(let job)):
                await JobStatusStore.shared.seedQueued(job)
                await rideAcceptJob(job)
            case .failure(let error):
                await MainActor.run {
                    isAccepting = false
                    // The server's message is the good one — it distinguishes a stale cache key
                    // from an unknown generation from missing audio better than a canned string.
                    statusMessage = nil
                    presentError(ServerError.detailedMessage(from: error), title: "Accept Failed")
                }
            }
        }
    }

    /// Follow a queued accept (audio assembly) to its end. The terminal result decodes as the
    /// same script body a 200 would have returned.
    private func rideAcceptJob(_ job: JobCreatedResponse) async {
        for await event in await JobStatusStore.shared.events(forJob: job.jobId) {
            switch event {
            case .updated(let info):
                let percent = Int((info.progress ?? 0) * 100)
                await MainActor.run {
                    statusMessage = "Assembling take audio… \(percent)%"
                }
            case .terminal(let info):
                await MainActor.run {
                    isAccepting = false
                    guard info.status == .completed else {
                        statusMessage = nil
                        presentError(
                            info.result ?? "The accept job failed on the server.",
                            title: "Accept Failed")
                        return
                    }
                    guard let result = info.result, let data = result.data(using: .utf8),
                        let canonical = try? JSONDecoder().decode(DialogScript.self, from: data)
                    else {
                        statusMessage = nil
                        presentError(
                            "The accept job finished but its result could not be decoded.",
                            title: "Accept Failed")
                        return
                    }
                    statusMessage = "Voice accepted"
                    onVoiceChanged?(canonical)
                }
                return
            case .removed:
                await MainActor.run {
                    isAccepting = false
                    statusMessage = nil
                    presentError(
                        "The accept job was removed before it finished.", title: "Accept Failed")
                }
                return
            }
        }
        await MainActor.run { isAccepting = false }
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

    private func playMeta(_ dto: DialogPreviewMetaDTO, token: UUID) async {
        guard token == requestToken else { return }

        #if os(macOS)
            if spatialAudition, let stage = spatialStage {
                await playMetaSpatially(dto, stage: stage, token: token)
                return
            }
        #endif
        await playMetaFlat(dto, token: token)
    }

    #if os(macOS)
        /// Spatial path: the take's 17-channel export, positioned on the bound stage. Falls back
        /// to the flat MP3 with a visible note rather than failing silent — the 17ch file can be
        /// missing for takes that predate export-at-generation.
        private func playMetaSpatially(
            _ dto: DialogPreviewMetaDTO, stage: Stage, token: UUID
        ) async {
            audioManager.stopURLPlayback()
            let soundFile: String
            let adHoc: Bool
            if dto.generationId == acceptedVoice?.generationId,
                let promoted = acceptedVoice?.soundFile, !promoted.isEmpty
            {
                // The accepted take's ad-hoc export moved on promotion; its permanent file is
                // the same 17-channel audio under the promoted name.
                soundFile = promoted
                adHoc = false
            } else {
                soundFile = "dialog-17ch-\(dto.generationId.uuidString.lowercased()).wav"
                adHoc = true
            }
            do {
                try await spatialPlayer.play(soundFile: soundFile, stage: stage, adHoc: adHoc)
                guard token == requestToken else { return }
                isWorking = false
                statusMessage =
                    "Playing spatially on \(stage.title.isEmpty ? "the stage" : stage.title)…"
            } catch {
                guard token == requestToken else { return }
                statusMessage = "Spatial audio unavailable for this take — playing flat."
                await playMetaFlat(dto, token: token, preserveStatus: true)
            }
        }
    #endif

    private func playMetaFlat(
        _ dto: DialogPreviewMetaDTO, token: UUID, preserveStatus: Bool = false
    ) async {
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
                if !preserveStatus {
                    statusMessage = "Playing preview…"
                }
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

    private func exportMono() {
        // Ensure we have meta (and therefore an audio URL) for the current selection.
        let token = UUID()
        requestToken = token
        isWorking = true
        statusMessage = "Fetching mono WAV…"
        let request = DialogPreviewRequest.fromTurns(
            previewTurns, generationId: meta?.generationId, title: title)
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
            previewTurns, generationId: meta?.generationId, title: title)
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
            previewTurns, generationId: meta?.generationId, title: title)
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

    private func presentError(_ message: String, title: String = "Preview Error") {
        errorAlert = ErrorAlert(title: title, message: message)
        statusMessage = nil
    }

    private func takeLabel(_ take: DialogPreviewLookupDTO.Generation, index: Int) -> String {
        if let date = take.createdAtDate {
            return
                "Take \(takes.count - index) • \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return
            "Take \(takes.count - index) • \(take.generationId.uuidString.lowercased().prefix(8))"
    }
}

private struct DialogMusicCandidate: Identifiable, Equatable {
    let result: DialogMusicGenerationResult
    let sourceCacheKey: String
    let sourceDialogGenerationId: DialogGenerationIdentifier
    var isExpired = false

    var id: UUID { result.musicGenerationId }

    /// A candidate is current iff it was composed against the *accepted* voice. Comparing to the
    /// last-auditioned take made warnings flap during A/B listening, and comparing to the
    /// script's updated_at stale-marked every candidate on ANY save — picking a stage was enough
    /// to orange-flag music whose voice hadn't changed at all.
    func matches(_ acceptedVoice: DialogAcceptedVoice?) -> Bool {
        guard let acceptedVoice else { return false }
        return sourceCacheKey.lowercased() == acceptedVoice.dialogCacheKey.lowercased()
            && sourceDialogGenerationId == acceptedVoice.generationId
    }
}

/// Music is deliberately downstream of a saved, full-dialog voice take. Keeping candidates in
/// session state makes experimentation cheap while promotion remains an explicit commit point.
struct DialogMusicPanel: View {
    let scriptId: DialogScriptIdentifier?
    /// Music is composed against the *accepted* voice — the audio that will actually render —
    /// never against whatever take happens to be auditioning.
    let acceptedVoice: DialogAcceptedVoice?
    /// Whether the acceptance still matches the current turns (computed by the editor).
    let acceptedVoiceIsFresh: Bool
    let backgroundMusic: DialogBackgroundMusic?
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
    @State private var jobSourceVoice: DialogAcceptedVoice?
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
        scriptId != nil && acceptedVoice != nil && acceptedVoiceIsFresh && !hasUnsavedChanges
            && !trimmedPrompt.isEmpty
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
        .onChange(of: acceptedVoice) { _, _ in
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
        if acceptedVoice == nil {
            return "Accept a voice take first — music is composed against the accepted voice."
        }
        if !acceptedVoiceIsFresh {
            return
                "The accepted voice take predates the current turns. Re-accept a take before generating music."
        }
        return nil
    }

    @ViewBuilder
    private func acceptedMusicCard(_ music: DialogBackgroundMusic) -> some View {
        // nil = server hasn't recorded which voice take this music was composed against
        // (pre-#136 acceptance) — unknown is shown as nothing, never as a false verdict.
        let matchesVoice = music.matchesAcceptedVoice(acceptedVoice)
        VStack(alignment: .leading, spacing: 8) {
            Label("Accepted music", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.headline)
            Text(music.prompt).font(.subheadline)

            if matchesVoice == false {
                Label(
                    "Composed against a different voice take than the accepted one — its timing may not match. Generate and accept a new candidate.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else if matchesVoice == nil {
                // Accepted before the server recorded provenance (server#136). Re-promoting
                // backfills from the audio's own iXML — no regeneration, one call.
                HStack(spacing: 8) {
                    Text("Not yet checked against the accepted voice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Check Voice Match") {
                        backfillProvenance(music)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(scriptId == nil || hasUnsavedChanges || isSubmitting)
                }
            }
            Text(music.soundFile)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Play with Dialog") { auditionAccepted(music) }
                    .disabled(acceptedVoice == nil || isAuditioning)
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
        let isCurrent = candidate.matches(acceptedVoice)
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
                    "Made for a different voice take than the accepted one — its timing won't match. Generate a new candidate.",
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
        guard let scriptId, let voice = acceptedVoice, canGenerate else { return }
        isSubmitting = true
        jobSourceVoice = voice
        statusMessage = "Starting music generation…"
        let request = DialogMusicRequest(
            scriptId: scriptId,
            dialogCacheKey: voice.dialogCacheKey,
            dialogGenerationId: voice.generationId,
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
            let sourceVoice = jobSourceVoice
        else {
            errorAlert = ErrorAlert(
                title: "Music Generation Failed",
                message: info.result ?? "The server did not return a music candidate.")
            statusMessage = nil
            return
        }
        let candidate = DialogMusicCandidate(
            result: result, sourceCacheKey: sourceVoice.dialogCacheKey,
            sourceDialogGenerationId: sourceVoice.generationId)
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
        guard !hasUnsavedChanges, candidate.matches(acceptedVoice) else { return }
        let promotionScriptId = scriptId
        let promotionVoice = acceptedVoice
        statusMessage = "Accepting music…"
        Task {
            switch await server.promoteDialogMusic(generationId: candidate.id) {
            case .success(let result):
                let accepted = DialogBackgroundMusic(
                    soundFile: result.soundFile,
                    generationId: result.musicGenerationId,
                    prompt: candidate.result.prompt,
                    acceptedAt: Int64(Date().timeIntervalSince1970 * 1_000),
                    // The candidate knows what it was composed against; the fallback card must
                    // not show "unknown" for a promotion that just happened.
                    sourceDialogGenerationId: candidate.sourceDialogGenerationId,
                    sourceDialogCacheKey: candidate.sourceCacheKey)
                if let scriptId {
                    switch await server.getDialogScript(id: scriptId) {
                    case .success(let canonical):
                        await MainActor.run {
                            guard scriptId == promotionScriptId,
                                acceptedVoice == promotionVoice,
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
                                acceptedVoice == promotionVoice,
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
                            acceptedVoice == promotionVoice,
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

    /// Repair pre-#136 accepted music: re-promoting the same generation makes the server
    /// backfill source provenance from the WAV's embedded iXML, after which the card can render
    /// a real verdict instead of silence.
    private func backfillProvenance(_ music: DialogBackgroundMusic) {
        guard let scriptId, !hasUnsavedChanges else { return }
        let repairScriptId = scriptId
        statusMessage = "Checking music against the accepted voice…"
        Task {
            switch await server.promoteDialogMusic(generationId: music.generationId) {
            case .success:
                switch await server.getDialogScript(id: scriptId) {
                case .success(let canonical):
                    await MainActor.run {
                        guard self.scriptId == repairScriptId, !hasUnsavedChanges else { return }
                        onScriptUpdated(canonical)
                        statusMessage = nil
                    }
                case .failure(let error):
                    await MainActor.run {
                        presentError("Checked, But Script Refresh Failed", error)
                    }
                }
            case .failure(let error):
                await MainActor.run { presentError("Could Not Check Music", error) }
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
        guard let voice = acceptedVoice,
            let musicURL = server.makeAbsoluteURL(fromRelativePath: candidate.result.mp3Url)
        else { return }
        audition(voice: voice, musicURL: musicURL, candidateId: candidate.id)
    }

    private func auditionAccepted(_ music: DialogBackgroundMusic) {
        guard let voice = acceptedVoice,
            case .success(let musicURL) = server.getSoundRenditionURL(music.soundFile, as: .mp3)
        else { return }
        audition(voice: voice, musicURL: musicURL, candidateId: nil)
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
        voice: DialogAcceptedVoice, musicURL: URL, candidateId: UUID?
    ) {
        guard
            case .success(let voiceURL) = server.dialogPreviewRenditionURL(
                cacheKey: voice.dialogCacheKey, generationId: voice.generationId, as: .mp3)
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
                            "preview-\(voice.dialogCacheKey)-\(voice.generationId.uuidString.lowercased())",
                        fileExtension: "mp3")
                    {
                    case .success(let localVoiceURL):
                        switch musicDownload {
                        case .success(let data):
                            switch audioManager.cacheAudioData(
                                data,
                                cacheKey: candidateId?.uuidString.lowercased()
                                    ?? "accepted-\(voice.dialogCacheKey)",
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
