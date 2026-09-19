import AVFoundation
import Common
import Foundation
import OSLog
import SwiftUI

/// The music editor. Start a piece from a description (or an empty plan), then refine it in
/// place: edit a section's name, directions, styles or length, add or split sections, and
/// **Apply** — only the changed sections are composed, every other section comes back
/// identical, and the result becomes the current piece. Every Apply is kept as a version;
/// accepting one for the final render is the explicit commit point.
///
/// Music is deliberately downstream of a saved, full-dialog voice take (see `MusicSubject`).
/// The same view is embedded by the dialog editor and shown by the sidebar's Music workspace.
struct MusicCreationView: View {
    let subject: MusicSubject
    /// Canonical script handed back by the server after promote / clear, for the owner to merge.
    let onScriptUpdated: (DialogScript) -> Void
    /// Local-only update when a promotion succeeded but the canonical refresh didn't.
    let onMusicUpdated: (DialogBackgroundMusic?) -> Void
    /// The editor shows its own numbered heading; the workspace wants the title instead.
    var heading: String? = "3. Background Music"

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MusicCreationView")
    private let server = CreatureServerClient.shared
    private let audioManager = AudioManager.shared

    // The piece
    @State private var piece = MusicPiece.blank()
    @State private var waveform = MusicWaveform.empty
    @State private var player = MusicPiecePlayer()
    /// Which version the piece's audio came from, if any.
    @State private var editingCandidateID: UUID?
    /// The piece as it was when Apply was pressed; committed when the job completes.
    @State private var pendingPiece: MusicPiece?
    /// Learned from the first plan draft or version; the piece must cover it.
    @State private var dialogDurationMilliseconds: Int64?

    // Starting a piece
    @State private var prompt = ""
    @State private var generationMode: DialogMusicGenerationMode = .track
    @State private var durationExtensionSeconds = 0.0
    @State private var allowVocals = false
    @State private var isDrafting = false

    // Shared knobs
    @State private var finetune: MusicFinetuneSelection?
    @State private var seedText = ""
    /// The finetune and seed the version being edited was made with (see MusicLibraryPieceView).
    @State private var baseFinetune: MusicFinetuneSelection?
    @State private var baseSeed: Int64?

    // Generation
    @State private var candidates: [DialogMusicCandidate] = []
    @State private var nextOrdinal = 1
    @State private var activeJobId: String?
    @State private var observedJob: JobStatusStore.JobInfo?
    @State private var jobSourceVoice: DialogAcceptedVoice?
    @State private var isSubmitting = false

    // Listening to a version against the dialog
    @State private var isAuditioning = false
    @State private var musicVolume = 0.35
    @State private var auditionToken = UUID()
    @State private var audioLoadToken = UUID()

    // Promotion / feedback
    @State private var candidateToPromote: DialogMusicCandidate?
    @State private var showReplacementConfirmation = false
    @State private var showClearConfirmation = false
    @State private var showStartOverConfirmation = false
    @State private var soundToShare: String?
    @State private var statusMessage: String?
    @State private var errorAlert: ErrorAlert?

    // The library
    @State private var showLibraryPicker = false
    @State private var candidateToSave: DialogMusicCandidate?
    @State private var libraryTitle = ""
    @State private var isSavingToLibrary = false

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var promptIsValid: Bool {
        !trimmedPrompt.isEmpty && trimmedPrompt.utf8.count <= DialogLimits.maxMusicPromptBytes
    }

    private var isBusy: Bool {
        isSubmitting || isDrafting || isSavingToLibrary
            || (observedJob.map { !$0.isTerminal } ?? false)
    }

    private var knownDialogDurationMilliseconds: Int64? {
        dialogDurationMilliseconds ?? subject.dialogDurationMilliseconds
    }

    private var seed: Int64? {
        let text = seedText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let value = Int64(text),
            (0...DialogLimits.maxMusicSeed).contains(value)
        else { return nil }
        return value
    }

    private var seedIsValid: Bool {
        seedText.trimmingCharacters(in: .whitespaces).isEmpty || seed != nil
    }

    private var hasPiece: Bool { !piece.sections.isEmpty }

    private var applyProblems: [String] {
        piece.refinementPlan().validationProblems(
            dialogDurationMilliseconds: dialogDurationMilliseconds)
    }

    private var knobsChanged: Bool {
        piece.hasAudio && seedIsValid && (finetune != baseFinetune || seed != baseSeed)
    }

    private var canApply: Bool {
        subject.canCompose && !isBusy && hasPiece && applyProblems.isEmpty && seedIsValid
            && (piece.isDirty || !piece.hasAudio || knobsChanged)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if let heading {
                    Text(heading).font(.title2.bold())
                }
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }

            if let backgroundMusic = subject.backgroundMusic {
                acceptedMusicCard(backgroundMusic)
            }

            if hasPiece {
                pieceEditor
            } else {
                starter
            }

            if let reason = subject.unavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let note = subject.freshnessNote {
                Label(note, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }

            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Versions").font(.headline)
                    ForEach(candidates) { candidate in
                        MusicCandidateCard(
                            candidate: candidate,
                            isCurrent: candidate.matches(subject.acceptedVoice),
                            isEditing: candidate.id == editingCandidateID,
                            isAccepted: subject.backgroundMusic?.generationId == candidate.id,
                            hasAcceptedMusic: subject.backgroundMusic != nil,
                            canPromote: !subject.hasUnsavedChanges,
                            isAuditioning: isAuditioning,
                            onAudition: { audition(candidate) },
                            onPromote: { requestPromotion(candidate) },
                            onMakeCurrent: { makeCurrent(candidate) },
                            onSaveToLibrary: { beginSavingToLibrary(candidate) })
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
        .panelCard()
        .watchJob(activeJobId) { info in
            observedJob = info
            let percent = Int((info.progress ?? 0) * 100)
            statusMessage = "Composing… \(percent)%"
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
        .onChange(of: subject.acceptedVoice) { _, _ in
            auditionToken = UUID()
            isAuditioning = false
            audioManager.stopDialogAudition()
        }
        .onDisappear {
            auditionToken = UUID()
            audioLoadToken = UUID()
            isAuditioning = false
            audioManager.stopDialogAudition()
            audioManager.stopURLPlayback()
            player.unload()
        }
        .shareableSoundFlow(fileName: $soundToShare)
        .errorAlert($errorAlert)
        .sheet(isPresented: $showLibraryPicker) {
            MusicLibraryPickerSheet(dialogDurationMilliseconds: knownDialogDurationMilliseconds) {
                piece, version in
                useLibraryPiece(piece, version: version)
            }
        }
        .alert(
            "Save to the library",
            isPresented: Binding(
                get: { candidateToSave != nil }, set: { if !$0 { candidateToSave = nil } })
        ) {
            TextField("Title", text: $libraryTitle)
            Button("Save") { saveToLibrary() }
                .disabled(libraryTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { candidateToSave = nil }
        } message: {
            Text(
                "The version becomes a piece in the music library, to reuse under other dialogs or refine on its own."
            )
        }
        .confirmationDialog(
            "Replace accepted background music?", isPresented: $showReplacementConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Music", role: .destructive) {
                if let candidateToPromote { promote(candidateToPromote) }
            }
            Button("Cancel", role: .cancel) { candidateToPromote = nil }
        } message: {
            Text("The newly accepted version will be used by future final renders.")
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
        .confirmationDialog(
            "Start a new piece?", isPresented: $showStartOverConfirmation,
            titleVisibility: .visible
        ) {
            Button("Start Over", role: .destructive) { startOver() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sections being edited are discarded. Versions already made stay listed.")
        }
    }

    // MARK: - Starting a piece

    @ViewBuilder
    private var starter: some View {
        Text("Start a piece").font(.headline)
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
                    trimmedPrompt.utf8.count > DialogLimits.maxMusicPromptBytes ? .red : .secondary)
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
            Slider(
                value: $durationExtensionSeconds,
                in: 0...Double(DialogLimits.maxMusicDurationExtensionMilliseconds / 1_000),
                step: 1)
            Text(
                "The final show lasts for whichever is longer: the dialog or accepted music. The dialog channels remain neutral during a music-only tail."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Toggle("Let the birds sing (allow vocals)", isOn: $allowVocals)

        MusicFinetunePicker(selection: $finetune)
            .font(.callout)

        HStack {
            Button {
                generateFirstTake()
            } label: {
                Label("Compose First Version", systemImage: "music.note.list")
            }
            .buttonStyle(.glassProminent)
            .disabled(!subject.canCompose || !promptIsValid || isBusy)
            .help("Let the server plan and compose the whole piece from this description")

            Button {
                draftPlan()
            } label: {
                Label("Draft Sections First", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.glass)
            .disabled(!subject.canCompose || !promptIsValid || isBusy)
            .help("Turn this description into sections you can edit before composing")

            Button {
                piece = MusicPiece.blank(sections: [
                    MusicGenerationChunk(
                        text: "[Intro]", durationMilliseconds: dialogDurationMilliseconds ?? 30_000)
                ])
                statusMessage = "Describe each section, then Compose."
            } label: {
                Label("Start Empty", systemImage: "plus")
            }
            .buttonStyle(.glass)
            .disabled(isBusy)
        }

        Button {
            showLibraryPicker = true
        } label: {
            Label("Use a Library Piece…", systemImage: "books.vertical")
        }
        .buttonStyle(.glass)
        .disabled(!subject.canCompose || isBusy)
        .help("Compose this dialog's music from a piece already in the library")
    }

    // MARK: - The piece

    @ViewBuilder
    private var pieceEditor: some View {
        MusicPieceEditor(
            piece: $piece, waveform: waveform, player: player,
            dialogDurationMilliseconds: dialogDurationMilliseconds)

        HStack(alignment: .top, spacing: 16) {
            MusicFinetunePicker(selection: $finetune)
            HStack {
                Text("Seed")
                TextField("random", text: $seedText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                if !seedIsValid {
                    Text("0–\(DialogLimits.maxMusicSeed)").foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
        .font(.callout)

        HStack {
            Button {
                apply()
            } label: {
                Label(piece.hasAudio ? "Apply Changes" : "Compose", systemImage: "wand.and.stars")
            }
            .buttonStyle(.glassProminent)
            .disabled(!canApply)
            .help(
                piece.hasAudio
                    ? "Compose only the changed sections; every other section stays exactly as it is"
                    : "Compose every section")

            Button("Revert") {
                piece = piece.reverted()
                finetune = baseFinetune
                seedText = baseSeed.map(String.init) ?? ""
                statusMessage = "Edits discarded."
            }
            .buttonStyle(.glass)
            .disabled(!piece.hasAudio || !(piece.isDirty || knobsChanged) || isBusy)

            Spacer()

            Button("Start Over") { showStartOverConfirmation = true }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(isBusy)
        }
        if knobsChanged {
            Label(
                "Finetune or seed changed: Apply composes every section again, in character with the current version.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// The knobs a version was made with become the baseline the next Apply is judged against.
    private func adoptKnobs(from recipe: DialogMusicRecipe?) {
        baseFinetune = recipe?.finetune
        baseSeed = recipe?.seed
        finetune = baseFinetune
        seedText = baseSeed.map(String.init) ?? ""
    }

    private func startOver() {
        player.unload()
        waveform = .empty
        piece = .blank()
        editingCandidateID = nil
        pendingPiece = nil
        statusMessage = nil
    }

    // MARK: - Accepted music

    @ViewBuilder
    private func acceptedMusicCard(_ music: DialogBackgroundMusic) -> some View {
        // nil = server hasn't recorded which voice take this music was composed against
        // (pre-#136 acceptance) — unknown is shown as nothing, never as a false verdict.
        let matchesVoice = music.matchesAcceptedVoice(subject.acceptedVoice)
        VStack(alignment: .leading, spacing: 8) {
            Label("Accepted music", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.headline)
            Text(music.prompt.isEmpty ? "Composed from sections" : music.prompt)
                .font(.subheadline)

            if matchesVoice == false {
                Label(
                    "Composed against a different voice take than the accepted one — its timing may not match. Compose and accept a new version.",
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
                    .disabled(subject.scriptId == nil || subject.hasUnsavedChanges || isSubmitting)
                }
            }
            Text(music.soundFile)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Play with Dialog") { auditionAccepted(music) }
                    .disabled(subject.acceptedVoice == nil || isAuditioning)
                Button("Share MP3…") { soundToShare = music.soundFile }
                Button {
                    openAcceptedInEditor(music)
                } label: {
                    Label("Edit in Place", systemImage: "slider.horizontal.3")
                }
                .help("Load the accepted music into the editor to refine it")
                .disabled(isBusy)
            }
            Button("Remove Accepted Music", role: .destructive) {
                showClearConfirmation = true
            }
            .buttonStyle(.borderless)
            .disabled(subject.scriptId == nil || subject.hasUnsavedChanges)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panelCard(cornerRadius: 10, tint: .green)
    }

    /// The accepted music as an editable piece: its recipe gives the song and the plan, its
    /// permanent MP3 gives the audio.
    private func openAcceptedInEditor(_ music: DialogBackgroundMusic) {
        isDrafting = true
        statusMessage = "Reading how the accepted music was made…"
        Task {
            let result = await server.getDialogMusicRecipe(generationId: music.generationId)
            await MainActor.run {
                isDrafting = false
                switch result {
                case .success(let recipe):
                    guard recipe.canBeReferenced, let plan = recipe.compositionPlan else {
                        errorAlert = ErrorAlert(
                            title: "Can't Refine This Music",
                            message:
                                "The server has no referenceable song for it, so its sections can't be kept while others change. Start a new piece instead."
                        )
                        statusMessage = nil
                        return
                    }
                    if let session = candidates.first(where: { $0.id == music.generationId }),
                        let snapshot = session.piece
                    {
                        piece = snapshot
                        editingCandidateID = session.id
                    } else {
                        piece = MusicPiece(
                            songId: recipe.songId,
                            durationMilliseconds: plan.totalDurationMilliseconds, plan: plan)
                        editingCandidateID = nil
                    }
                    adoptKnobs(from: recipe)
                    if case .success(let url) = server.getSoundRenditionURL(
                        music.soundFile, as: .mp3)
                    {
                        loadAudio(
                            from: url,
                            cacheKey:
                                "accepted-music-\(music.generationId.uuidString.lowercased())")
                    }
                    statusMessage =
                        "Editing the accepted music. Change what you like, then Apply."
                case .failure(.notFound):
                    errorAlert = ErrorAlert(
                        title: "Recipe Unavailable",
                        message:
                            "The server no longer has this music's recipe: it aged out of the candidate cache. Start a new piece instead."
                    )
                    statusMessage = nil
                case .failure(let error):
                    presentError("Could Not Read Recipe", error)
                }
            }
        }
    }

    // MARK: - Drafting and composing

    private func draftPlan() {
        guard let voice = subject.acceptedVoice, subject.canCompose, promptIsValid else { return }
        isDrafting = true
        statusMessage = "Drafting sections…"
        let request = DialogMusicPlanRequest(
            dialogCacheKey: voice.dialogCacheKey,
            dialogGenerationId: voice.generationId,
            prompt: trimmedPrompt,
            durationExtensionMilliseconds: Int64(durationExtensionSeconds * 1_000))
        Task {
            let result = await server.draftDialogMusicPlan(request)
            await MainActor.run {
                isDrafting = false
                switch result {
                case .success(let drafted):
                    dialogDurationMilliseconds = drafted.dialogDurationMilliseconds
                    piece = MusicPiece.blank(
                        sections: drafted.compositionPlan.chunks.compactMap { chunk in
                            if case .generation(let generation) = chunk {
                                return allowVocals
                                    ? generation.unconditioned()
                                    : generation.unconditioned().instrumental()
                            }
                            return nil
                        })
                    editingCandidateID = nil
                    statusMessage =
                        "Drafted \(piece.sections.count) section(s) over \(TimeHelper.formatDuration(Double(drafted.musicLengthMilliseconds) / 1_000)). Edit, then Compose."
                case .failure(let error):
                    presentError("Could Not Draft Sections", error)
                }
            }
        }
    }

    private func generateFirstTake() {
        guard let scriptId = subject.scriptId, let voice = subject.acceptedVoice,
            subject.canCompose, promptIsValid, !isBusy
        else { return }
        pendingPiece = nil
        submit(
            DialogMusicRequest(
                scriptId: scriptId,
                dialogCacheKey: voice.dialogCacheKey,
                dialogGenerationId: voice.generationId,
                composition: .prompt(
                    DialogMusicRequest.Prompt(
                        prompt: trimmedPrompt,
                        durationExtensionMilliseconds: Int64(durationExtensionSeconds * 1_000),
                        generationMode: generationMode,
                        forceInstrumental: !allowVocals)),
                finetune: finetune),
            voice: voice, message: "Composing the first version…")
    }

    private func apply() {
        guard let scriptId = subject.scriptId, let voice = subject.acceptedVoice, canApply
        else { return }
        let plan = piece.refinementPlan(recomposeAll: knobsChanged)
        pendingPiece = piece
        let composed = plan.chunks.filter { !$0.isAudioReference }.count
        let kept = plan.chunks.count - composed
        submit(
            DialogMusicRequest(
                scriptId: scriptId,
                dialogCacheKey: voice.dialogCacheKey,
                dialogGenerationId: voice.generationId,
                composition: .plan(plan, seed: seed),
                finetune: finetune),
            voice: voice,
            message: !piece.hasAudio
                ? "Composing \(composed) section(s)…"
                : (knobsChanged
                    ? "Composing every section again with the new finetune or seed, in character…"
                    : "Composing \(composed) section(s); keeping \(kept)…"))
    }

    private func submit(_ request: DialogMusicRequest, voice: DialogAcceptedVoice, message: String)
    {
        isSubmitting = true
        jobSourceVoice = voice
        statusMessage = message
        Task {
            let result = await server.generateDialogMusic(request)
            await MainActor.run {
                isSubmitting = false
                switch result {
                case .success(let job):
                    Task { await JobStatusStore.shared.seedQueued(job) }
                    activeJobId = job.jobId
                case .failure(let error):
                    pendingPiece = nil
                    presentError("Composition Failed", error)
                }
            }
        }
    }

    private func finishGeneration(_ info: JobStatusStore.JobInfo) {
        defer { activeJobId = nil }
        guard info.status == .completed, let result = info.dialogMusicResult,
            let sourceVoice = jobSourceVoice
        else {
            pendingPiece = nil
            errorAlert = ErrorAlert(
                title: "Composition Failed",
                message: info.result ?? "The server did not return a version.")
            statusMessage = nil
            return
        }
        dialogDurationMilliseconds = result.dialogDurationMilliseconds

        // The piece this version *is*: the pending edits committed onto the new song, or,
        // for a first take from a description, the plan the server used.
        var committed: MusicPiece?
        if let recipe = result.recipe, recipe.canBeReferenced {
            if let pendingPiece {
                committed = pendingPiece.committed(
                    songId: recipe.songId, durationMilliseconds: result.durationMilliseconds)
            } else if let plan = recipe.compositionPlan {
                committed = MusicPiece(
                    songId: recipe.songId, durationMilliseconds: result.durationMilliseconds,
                    plan: plan)
            }
        }
        pendingPiece = nil

        let candidate = DialogMusicCandidate(
            result: result, sourceCacheKey: sourceVoice.dialogCacheKey,
            sourceDialogGenerationId: sourceVoice.generationId, ordinal: nextOrdinal,
            piece: committed)
        nextOrdinal += 1
        candidates.insert(candidate, at: 0)

        if let committed {
            piece = committed
            editingCandidateID = candidate.id
            adoptKnobs(from: result.recipe)
            statusMessage = "\(candidate.label) ready — every section now matches its audio."
        } else {
            statusMessage =
                "\(candidate.label) ready, but the server kept no referenceable song for it, so it can't be refined."
        }
        if let url = server.makeAbsoluteURL(fromRelativePath: result.mp3Url) {
            loadAudio(from: url, cacheKey: candidate.id.uuidString.lowercased())
        }
    }

    /// Make an earlier version the piece being edited, with its audio under the timeline.
    private func makeCurrent(_ candidate: DialogMusicCandidate) {
        guard let editable = candidate.editablePiece else { return }
        piece = editable
        editingCandidateID = candidate.id
        adoptKnobs(from: candidate.result.recipe)
        statusMessage = "Editing \(candidate.label)."
        if let url = server.makeAbsoluteURL(fromRelativePath: candidate.result.mp3Url) {
            loadAudio(from: url, cacheKey: candidate.id.uuidString.lowercased())
        }
    }

    /// Download the piece's audio, hand it to the player and draw its waveform.
    private func loadAudio(from url: URL, cacheKey: String) {
        let token = UUID()
        audioLoadToken = token
        waveform = .empty
        Task {
            let outcome = await player.loadRemote(url: url, cacheKey: cacheKey)
            guard token == audioLoadToken else { return }
            switch outcome {
            case .success(let decoded):
                waveform = decoded
            case .failure(let error):
                if error.isExpired,
                    let index = candidates.firstIndex(where: {
                        $0.id.uuidString.lowercased() == cacheKey
                    })
                {
                    candidates[index].isExpired = true
                    statusMessage = "That version's audio has expired on the server."
                } else {
                    errorAlert = ErrorAlert(title: "Could Not Load Audio", message: error.message)
                }
            }
        }
    }

    // MARK: - The library

    /// Compose this dialog's music from a saved piece: its current version is referenced
    /// section by section, and when the dialog runs longer a matching tail is composed.
    private func useLibraryPiece(_ saved: SavedMusicPiece, version: SavedMusicVersion) {
        guard let scriptId = subject.scriptId, let voice = subject.acceptedVoice,
            subject.canCompose, !isBusy
        else { return }
        var chunks: [MusicPlanChunk] = []
        var offset: Int64 = 0
        for section in version.sections {
            let end = offset + section.durationMilliseconds
            chunks.append(
                .audioReference(
                    MusicAudioRange(
                        songId: version.songId, startMilliseconds: offset, endMilliseconds: end)))
            offset = end
        }
        if chunks.isEmpty {
            chunks.append(
                .audioReference(
                    MusicAudioRange(
                        songId: version.songId, startMilliseconds: 0,
                        endMilliseconds: min(
                            version.durationMilliseconds, DialogLimits.maxMusicChunkMilliseconds))))
        }
        if let dialog = knownDialogDurationMilliseconds, dialog > version.durationMilliseconds {
            let tail = max(
                dialog - version.durationMilliseconds, DialogLimits.minMusicChunkMilliseconds)
            let last = version.sections.last
            chunks.append(
                .generation(
                    MusicGenerationChunk(
                        text: "[Continuation] carries the piece on to the end of the dialog",
                        durationMilliseconds: tail,
                        positiveStyles: last?.positiveStyles ?? [],
                        negativeStyles: last?.negativeStyles ?? [],
                        contextAdherence: .high,
                        conditioningReference: MusicAudioRange.referenceSpan(
                            of: version.songId, durationMilliseconds: version.durationMilliseconds),
                        conditionStrength: .high)))
        }
        let plan = MusicCompositionPlan(chunks: chunks)
        // The piece as it will be after this take: its sections, moved onto the new song.
        pendingPiece = MusicPiece.blank(sections: version.sections.map { $0.unconditioned() })
        submit(
            DialogMusicRequest(
                scriptId: scriptId,
                dialogCacheKey: voice.dialogCacheKey,
                dialogGenerationId: voice.generationId,
                composition: .plan(plan, seed: version.recipe?.seed),
                finetune: version.recipe?.finetune),
            voice: voice,
            message: "Composing this dialog's music from “\(saved.title)”…")
    }

    private func beginSavingToLibrary(_ candidate: DialogMusicCandidate) {
        libraryTitle = subject.title
        candidateToSave = candidate
    }

    private func saveToLibrary() {
        guard let candidate = candidateToSave else { return }
        let title = libraryTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        candidateToSave = nil
        isSavingToLibrary = true
        statusMessage = "Saving “\(title)” to the library…"
        let sections = candidate.piece?.serverSections ?? candidate.result.recipe?.sections
        Task {
            let outcome = await server.saveMusicCandidate(
                generationId: candidate.id, MusicSaveRequest(title: title, sections: sections))
            await MainActor.run {
                isSavingToLibrary = false
                switch outcome {
                case .success(let saved):
                    statusMessage = "“\(saved.title)” is in the library."
                case .failure(let error):
                    presentError("Could Not Save to the Library", error)
                }
            }
        }
    }

    // MARK: - Promotion

    private func requestPromotion(_ candidate: DialogMusicCandidate) {
        candidateToPromote = candidate
        if subject.backgroundMusic == nil {
            promote(candidate)
        } else {
            showReplacementConfirmation = true
        }
    }

    private func promote(_ candidate: DialogMusicCandidate) {
        guard !subject.hasUnsavedChanges, candidate.matches(subject.acceptedVoice) else { return }
        let promotionScriptId = subject.scriptId
        let promotionVoice = subject.acceptedVoice
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
                if let scriptId = promotionScriptId {
                    switch await server.getDialogScript(id: scriptId) {
                    case .success(let canonical):
                        await MainActor.run {
                            guard subject.scriptId == promotionScriptId,
                                subject.acceptedVoice == promotionVoice,
                                !subject.hasUnsavedChanges
                            else { return }
                            onScriptUpdated(canonical)
                            candidateToPromote = nil
                            statusMessage = "Music accepted for final render"
                        }
                    case .failure(let error):
                        await MainActor.run {
                            guard subject.scriptId == promotionScriptId,
                                subject.acceptedVoice == promotionVoice,
                                !subject.hasUnsavedChanges
                            else { return }
                            // Promotion succeeded; retain that local state, but make the
                            // follow-up canonical-read failure visible instead of pretending
                            // the script revision is known.
                            onMusicUpdated(accepted)
                            candidateToPromote = nil
                            presentError("Music Accepted, But Script Refresh Failed", error)
                        }
                    }
                } else {
                    await MainActor.run {
                        guard subject.scriptId == promotionScriptId,
                            subject.acceptedVoice == promotionVoice,
                            !subject.hasUnsavedChanges
                        else { return }
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
        guard let scriptId = subject.scriptId, !subject.hasUnsavedChanges else { return }
        statusMessage = "Checking music against the accepted voice…"
        Task {
            switch await server.promoteDialogMusic(generationId: music.generationId) {
            case .success:
                switch await server.getDialogScript(id: scriptId) {
                case .success(let canonical):
                    await MainActor.run {
                        guard subject.scriptId == scriptId, !subject.hasUnsavedChanges else {
                            return
                        }
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
        guard let scriptId = subject.scriptId else { return }
        statusMessage = "Removing accepted music…"
        Task {
            switch await server.clearDialogMusic(scriptId: scriptId) {
            case .success(let canonical):
                await MainActor.run {
                    guard subject.scriptId == scriptId, !subject.hasUnsavedChanges else { return }
                    onScriptUpdated(canonical)
                    statusMessage = "Accepted music removed"
                }
            case .failure(let error):
                await MainActor.run { presentError("Could Not Remove Music", error) }
            }
        }
    }

    // MARK: - Listening against the dialog

    private func audition(_ candidate: DialogMusicCandidate) {
        guard let voice = subject.acceptedVoice,
            let musicURL = server.makeAbsoluteURL(fromRelativePath: candidate.result.mp3Url)
        else { return }
        audition(voice: voice, musicURL: musicURL, candidateId: candidate.id)
    }

    private func auditionAccepted(_ music: DialogBackgroundMusic) {
        guard let voice = subject.acceptedVoice,
            case .success(let musicURL) = server.getSoundRenditionURL(music.soundFile, as: .mp3)
        else { return }
        audition(voice: voice, musicURL: musicURL, candidateId: nil)
    }

    private func audition(voice: DialogAcceptedVoice, musicURL: URL, candidateId: UUID?) {
        // The accepted voice's promoted file is permanent; the audition-cache copy expires
        // with the 24 h TTL and is gone for any script accepted a while ago. Prefer the one
        // that always works, as the Voice Take panel does.
        let voiceURLResult: Result<URL, ServerError>
        if let soundFile = voice.soundFile, !soundFile.isEmpty {
            voiceURLResult = server.getSoundRenditionURL(soundFile, as: .mp3)
        } else {
            voiceURLResult = server.dialogPreviewRenditionURL(
                cacheKey: voice.dialogCacheKey, generationId: voice.generationId, as: .mp3)
        }
        guard case .success(let voiceURL) = voiceURLResult else {
            errorAlert = ErrorAlert(
                title: "Audition Failed", message: "Could not build the dialog MP3 URL.")
            return
        }
        player.pause()
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
        isDrafting = false
    }
}
