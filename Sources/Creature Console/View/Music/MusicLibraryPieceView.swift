import Common
import Foundation
import OSLog
import SwiftUI

/// The big editor: a piece of music that exists on its own. Start one from a description (or
/// empty sections), then refine it — edit sections by hand or type an instruction and let the
/// server propose the changes — and Apply. The server composes only the changed sections and
/// keeps the rest from the current version; every Apply is saved as a new version of the piece.
struct MusicLibraryPieceView: View {
    /// Nil starts a new piece.
    let pieceId: UUID?

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MusicLibraryPieceView")
    private let server = CreatureServerClient.shared

    // The record and the piece being edited
    @State private var saved: SavedMusicPiece?
    @State private var piece = MusicPiece.blank()
    @State private var waveform = MusicWaveform.empty
    @State private var player = MusicPiecePlayer()
    /// The saved version the piece's audio came from, and that a refinement builds on.
    @State private var editingVersionId: UUID?
    @State private var pendingPiece: MusicPiece?
    @State private var isLoading = false
    @State private var loadError: String?

    // Starting a piece
    @State private var prompt = ""
    @State private var lengthSeconds = 30.0
    @State private var generationMode: DialogMusicGenerationMode = .track
    @State private var allowVocals = false
    @State private var isDrafting = false

    // Shared knobs
    @State private var finetune: MusicFinetuneSelection?
    @State private var seedText = ""
    /// The finetune and seed the version being edited was made with. Changing either is a
    /// change to the whole piece: kept sections can't take on a new finetune, so Apply
    /// composes everything again, in character.
    @State private var baseFinetune: MusicFinetuneSelection?
    @State private var baseSeed: Int64?

    // The instruction box
    @State private var instruction = ""
    @State private var isRefining = false

    // Title and notes
    @State private var title = ""
    @State private var notes = ""

    // Composing
    @State private var activeJobId: String?
    @State private var observedJob: JobStatusStore.JobInfo?
    @State private var isSubmitting = false
    @State private var isSaving = false
    /// A finished take for a piece that doesn't exist on the server yet; saved once titled.
    @State private var unsavedTake: DialogMusicGenerationResult?
    @State private var showTitlePrompt = false
    @State private var draftTitle = ""

    // Feedback
    @State private var statusMessage: String?
    @State private var errorAlert: ErrorAlert?
    @State private var showStartOverConfirmation = false

    private var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var promptIsValid: Bool {
        !trimmedPrompt.isEmpty && trimmedPrompt.utf8.count <= DialogLimits.maxMusicPromptBytes
    }
    private var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isBusy: Bool {
        isSubmitting || isDrafting || isRefining || isSaving || isLoading
            || (observedJob.map { !$0.isTerminal } ?? false)
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
    private var baseVersion: SavedMusicVersion? {
        guard let saved else { return nil }
        if let editingVersionId, let version = saved.version(withId: editingVersionId) {
            return version
        }
        return saved.currentVersion
    }
    private var applyProblems: [String] {
        piece.refinementPlan().validationProblems(dialogDurationMilliseconds: nil)
    }
    private var knobsChanged: Bool {
        piece.hasAudio && seedIsValid && (finetune != baseFinetune || seed != baseSeed)
    }
    private var canApply: Bool {
        !isBusy && hasPiece && applyProblems.isEmpty && seedIsValid
            && (piece.isDirty || !piece.hasAudio || knobsChanged)
    }
    private var lengthMilliseconds: Int64 { Int64(lengthSeconds * 1_000) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading, saved == nil {
                    ProgressView("Loading piece…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Could Not Load Piece", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    if saved != nil {
                        header
                    }
                    if hasPiece {
                        editor
                    } else {
                        starter
                    }
                    if let statusMessage {
                        Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if let saved, !saved.versions.isEmpty {
                        versions(of: saved)
                    }
                }
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle(saved.map { $0.title.isEmpty ? "Piece" : $0.title } ?? "New Piece")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: pieceId) { await load() }
        .watchJob(activeJobId) { info in
            observedJob = info
            statusMessage = "Composing… \(Int((info.progress ?? 0) * 100))%"
        } onTerminal: { info in
            observedJob = info
            finishGeneration(info)
        } onRemoved: {
            activeJobId = nil
            statusMessage = nil
        }
        .onDisappear { player.unload() }
        .errorAlert($errorAlert)
        .alert("Name this piece", isPresented: $showTitlePrompt) {
            TextField("Title", text: $draftTitle)
            Button("Save to Library") { saveNewPiece() }
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The take becomes the first version of a new piece in the library.")
        }
        .confirmationDialog(
            "Start over?", isPresented: $showStartOverConfirmation, titleVisibility: .visible
        ) {
            Button("Start Over", role: .destructive) { startOver() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sections being edited are discarded. Saved versions are untouched.")
        }
    }

    // MARK: - Header (title, notes)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3.bold())
                .onSubmit { commitTitleAndNotes() }
            TextField("Notes", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit { commitTitleAndNotes() }
            if let saved, title != saved.title || notes != saved.notes {
                Button("Save Title and Notes") { commitTitleAndNotes() }
                    .buttonStyle(.glass)
                    .disabled(isBusy)
            }
        }
        .padding(16)
        .panelCard()
    }

    // MARK: - Starting a piece

    @ViewBuilder
    private var starter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a piece").font(.headline)
            TextField(
                "Describe the score, mood, instruments, and pacing…", text: $prompt, axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
            HStack {
                Text("Length")
                Slider(value: $lengthSeconds, in: 3...600, step: 1)
                Text(TimeHelper.formatDuration(lengthSeconds))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            Picker("Generation style", selection: $generationMode) {
                Text("Track").tag(DialogMusicGenerationMode.track)
                Text("Loop").tag(DialogMusicGenerationMode.loop)
                Text("Ambience").tag(DialogMusicGenerationMode.ambience)
            }
            .pickerStyle(.segmented)
            Toggle("Let the birds sing (allow vocals)", isOn: $allowVocals)
            MusicFinetunePicker(selection: $finetune).font(.callout)
            HStack {
                Button {
                    composeFirstVersion()
                } label: {
                    Label("Compose First Version", systemImage: "music.note.list")
                }
                .buttonStyle(.glassProminent)
                .disabled(!promptIsValid || isBusy)
                Button {
                    draftSections()
                } label: {
                    Label("Draft Sections First", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.glass)
                .disabled(!promptIsValid || isBusy)
                Button {
                    piece = MusicPiece.blank(sections: [
                        MusicGenerationChunk(
                            text: "[Intro]", durationMilliseconds: lengthMilliseconds)
                    ])
                    statusMessage = "Describe each section, then Compose."
                } label: {
                    Label("Start Empty", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .disabled(isBusy)
            }
        }
        .padding(16)
        .panelCard()
    }

    // MARK: - The editor

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if saved != nil {
                instructionBox
            }
            MusicPieceEditor(
                piece: $piece, waveform: waveform, player: player, dialogDurationMilliseconds: nil)

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
                    Label(
                        piece.hasAudio ? "Apply Changes" : "Compose",
                        systemImage: "wand.and.stars")
                }
                .buttonStyle(.glassProminent)
                .disabled(!canApply)
                .help(
                    piece.hasAudio
                        ? "Compose only the changed sections and save the result as a new version"
                        : "Compose every section")
                if isBusy {
                    ProgressView().controlSize(.small)
                }
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
        .padding(16)
        .panelCard()
    }

    private var instructionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Refine with an instruction").font(.subheadline.bold())
            HStack(alignment: .top) {
                TextField(
                    "e.g. add smooth synth pads and some ambient atmosphere", text: $instruction,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit { refine() }
                Button {
                    refine()
                } label: {
                    Label("Propose", systemImage: "sparkles")
                }
                .buttonStyle(.glass)
                .disabled(trimmedInstruction.isEmpty || isBusy || baseVersion == nil)
            }
            Text(
                "The server rewrites the sections to follow the instruction and marks what changed. Nothing is composed until you Apply."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Versions

    @ViewBuilder
    private func versions(of saved: SavedMusicPiece) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Versions").font(.headline)
            let ordered = saved.versions.sorted { $0.createdAt > $1.createdAt }
            ForEach(ordered) { version in
                let ordinal =
                    (saved.versions.sorted { $0.createdAt < $1.createdAt }
                        .firstIndex(where: { $0.id == version.id }) ?? 0) + 1
                let isCurrent = saved.currentVersion?.id == version.id
                let isEditing = editingVersionId == version.id
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Version \(ordinal)").font(.subheadline.bold())
                        if isCurrent {
                            Text("current")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular.tint(.green.opacity(0.3)), in: .capsule)
                        }
                        if isEditing {
                            Text("editing")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular.tint(.accentColor.opacity(0.3)), in: .capsule)
                        }
                        Spacer()
                        Text(version.createdAtDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(versionDetail(version, in: saved))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button {
                            edit(version: version)
                        } label: {
                            Label("Open", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.glass)
                        .disabled(isBusy || isEditing)
                        if !isCurrent {
                            Button("Make Current") { makeCurrent(version) }
                                .buttonStyle(.glass)
                                .disabled(isBusy)
                        }
                    }
                }
                .padding(12)
                .panelCard(
                    cornerRadius: 10, tint: isEditing ? .accentColor : (isCurrent ? .green : nil))
            }
        }
    }

    private func versionDetail(_ version: SavedMusicVersion, in saved: SavedMusicPiece) -> String {
        var parts = [
            TimeHelper.formatDuration(Double(version.durationMilliseconds) / 1_000),
            "\(version.sections.count) section(s)",
        ]
        if let baseId = version.baseVersionId,
            let index = saved.versions.sorted(by: { $0.createdAt < $1.createdAt })
                .firstIndex(where: { $0.id == baseId })
        {
            parts.append("refined from Version \(index + 1)")
        }
        if let seed = version.recipe?.seed { parts.append("seed \(seed)") }
        if version.sourceDialog != nil { parts.append("from a dialog") }
        if !version.canBeReferenced { parts.append("not kept at ElevenLabs") }
        return parts.joined(separator: " • ")
    }

    // MARK: - Loading

    private func load() async {
        guard let pieceId else {
            saved = nil
            return
        }
        isLoading = true
        loadError = nil
        switch await server.getMusicPiece(id: pieceId) {
        case .success(let record):
            adopt(record)
            if let current = record.currentVersion {
                edit(version: current)
            }
        case .failure(let error):
            loadError = ServerError.detailedMessage(from: error)
        }
        isLoading = false
    }

    private func adopt(_ record: SavedMusicPiece) {
        saved = record
        title = record.title
        notes = record.notes
    }

    /// Make a saved version the piece being edited, with its audio under the timeline.
    private func edit(version: SavedMusicVersion) {
        piece = MusicPiece(version: version)
        editingVersionId = version.id
        adoptKnobs(from: version.recipe)
        guard let url = server.makeAbsoluteURL(fromRelativePath: version.mp3Url) else { return }
        Task {
            waveform = .empty
            switch await player.loadRemote(
                url: url, cacheKey: "music-version-\(version.id.uuidString.lowercased())")
            {
            case .success(let decoded):
                waveform = decoded
            case .failure(let error):
                errorAlert = ErrorAlert(title: "Could Not Load Audio", message: error.message)
            }
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
        editingVersionId = nil
        pendingPiece = nil
        unsavedTake = nil
        statusMessage = nil
    }

    // MARK: - Title and notes

    private func commitTitleAndNotes() {
        guard let saved, title != saved.title || notes != saved.notes else { return }
        let request = MusicPieceUpdateRequest(
            title: title != saved.title ? title : nil, notes: notes != saved.notes ? notes : nil)
        isSaving = true
        Task {
            let result = await server.updateMusicPiece(id: saved.id, request)
            await MainActor.run {
                isSaving = false
                switch result {
                case .success(let record):
                    adopt(record)
                    statusMessage = "Saved."
                case .failure(let error):
                    presentError("Could Not Save", error)
                }
            }
        }
    }

    private func makeCurrent(_ version: SavedMusicVersion) {
        guard let saved else { return }
        isSaving = true
        Task {
            let result = await server.updateMusicPiece(
                id: saved.id, MusicPieceUpdateRequest(currentVersionId: version.id))
            await MainActor.run {
                isSaving = false
                switch result {
                case .success(let record):
                    adopt(record)
                    statusMessage = "This version now plays for the piece."
                case .failure(let error):
                    presentError("Could Not Change the Current Version", error)
                }
            }
        }
    }

    // MARK: - Drafting, proposing, composing

    private func draftSections() {
        guard promptIsValid else { return }
        isDrafting = true
        statusMessage = "Drafting sections…"
        let request = MusicPlanRequest(
            prompt: trimmedPrompt, musicLengthMilliseconds: lengthMilliseconds)
        Task {
            let result = await server.draftMusicPlan(request)
            await MainActor.run {
                isDrafting = false
                switch result {
                case .success(let drafted):
                    piece = MusicPiece.blank(
                        sections: drafted.sections.map {
                            allowVocals ? $0.unconditioned() : $0.unconditioned().instrumental()
                        })
                    statusMessage =
                        "Drafted \(drafted.sections.count) section(s) over \(TimeHelper.formatDuration(Double(drafted.musicLengthMilliseconds) / 1_000)). Edit, then Compose."
                case .failure(let error):
                    presentError("Could Not Draft Sections", error)
                }
            }
        }
    }

    private func refine() {
        guard let saved, let base = baseVersion, !trimmedInstruction.isEmpty else { return }
        isRefining = true
        statusMessage = "Asking for a proposal…"
        Task {
            let result = await server.refineMusicPiece(
                id: saved.id,
                MusicRefineRequest(instruction: trimmedInstruction, versionId: base.id))
            await MainActor.run {
                isRefining = false
                switch result {
                case .success(let proposal):
                    piece = piece.applying(proposal: proposal.sections)
                    statusMessage =
                        "Proposed: \(proposal.changed.count) section(s) change, \(proposal.kept.count) stay. Review the chips, then Apply."
                    instruction = ""
                case .failure(let error):
                    presentError("Could Not Propose Changes", error)
                }
            }
        }
    }

    private func composeFirstVersion() {
        guard promptIsValid, !isBusy else { return }
        pendingPiece = nil
        submit(
            MusicGenerateRequest(
                composition: .prompt(
                    DialogMusicRequest.Prompt(
                        prompt: trimmedPrompt, generationMode: generationMode,
                        forceInstrumental: !allowVocals),
                    musicLengthMilliseconds: lengthMilliseconds),
                pieceId: saved?.id, finetune: finetune),
            message: "Composing the first version…")
    }

    private func apply() {
        guard canApply else { return }
        pendingPiece = piece
        let base = piece.hasAudio ? baseVersion : nil
        // A new finetune or seed can't be applied to a kept section, so nothing is kept; the
        // base still conditions every section so the piece stays in character.
        let kept = knobsChanged ? [] : (base.map { piece.keptIndices(against: $0.sections) } ?? [])
        let changed = piece.sections.count - kept.count
        submit(
            MusicGenerateRequest(
                composition: .sections(
                    piece.serverSections, baseVersionId: base?.id, keep: kept,
                    conditionStrength: base == nil ? nil : .medium, seed: seed),
                pieceId: saved?.id, finetune: finetune),
            message: base == nil
                ? "Composing \(piece.sections.count) section(s)…"
                : (knobsChanged
                    ? "Composing every section again with the new finetune or seed, in character…"
                    : "Composing \(changed) section(s); keeping \(kept.count)…"))
    }

    private func submit(_ request: MusicGenerateRequest, message: String) {
        isSubmitting = true
        statusMessage = message
        Task {
            let result = await server.generateMusic(request)
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
        guard info.status == .completed, let result = info.dialogMusicResult else {
            pendingPiece = nil
            errorAlert = ErrorAlert(
                title: "Composition Failed",
                message: info.result ?? "The server did not return a take.")
            statusMessage = nil
            return
        }
        if let saved {
            saveVersion(result, of: saved)
        } else {
            unsavedTake = result
            draftTitle = title.isEmpty ? "" : title
            statusMessage = "Take ready. Name the piece to save it to the library."
            showTitlePrompt = true
        }
    }

    /// A take for an existing piece becomes its newest version straight away: the server is
    /// the record, and the piece being edited moves onto the new song.
    private func saveVersion(_ result: DialogMusicGenerationResult, of saved: SavedMusicPiece) {
        isSaving = true
        statusMessage = "Saving the new version…"
        let sections = pendingPiece?.serverSections ?? result.recipe?.sections
        Task {
            let outcome = await server.saveMusicCandidate(
                generationId: result.musicGenerationId,
                MusicSaveRequest(pieceId: saved.id, sections: sections))
            await MainActor.run {
                isSaving = false
                switch outcome {
                case .success(let record):
                    adopt(record)
                    if let version = record.version(withId: result.musicGenerationId) {
                        if let pendingPiece {
                            piece = pendingPiece.committed(version: version)
                        } else {
                            piece = MusicPiece(version: version)
                        }
                        editingVersionId = version.id
                        adoptKnobs(from: version.recipe)
                        statusMessage =
                            "Saved as a new version — every section now matches its audio."
                        loadAudio(of: version)
                    }
                    pendingPiece = nil
                case .failure(let error):
                    pendingPiece = nil
                    presentError("Composed, But Could Not Save the Version", error)
                }
            }
        }
    }

    private func saveNewPiece() {
        guard let take = unsavedTake else { return }
        let newTitle = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty else { return }
        isSaving = true
        statusMessage = "Saving “\(newTitle)” to the library…"
        let sections = pendingPiece?.serverSections ?? take.recipe?.sections
        Task {
            let outcome = await server.saveMusicCandidate(
                generationId: take.musicGenerationId,
                MusicSaveRequest(title: newTitle, sections: sections))
            await MainActor.run {
                isSaving = false
                switch outcome {
                case .success(let record):
                    adopt(record)
                    unsavedTake = nil
                    if let version = record.version(withId: take.musicGenerationId) {
                        if let pendingPiece {
                            piece = pendingPiece.committed(version: version)
                        } else {
                            piece = MusicPiece(version: version)
                        }
                        editingVersionId = version.id
                        adoptKnobs(from: version.recipe)
                        loadAudio(of: version)
                    }
                    pendingPiece = nil
                    statusMessage = "“\(newTitle)” is in the library."
                case .failure(let error):
                    presentError("Could Not Save the Piece", error)
                }
            }
        }
    }

    private func loadAudio(of version: SavedMusicVersion) {
        guard let url = server.makeAbsoluteURL(fromRelativePath: version.mp3Url) else { return }
        Task {
            waveform = .empty
            switch await player.loadRemote(
                url: url, cacheKey: "music-version-\(version.id.uuidString.lowercased())")
            {
            case .success(let decoded):
                waveform = decoded
            case .failure(let error):
                errorAlert = ErrorAlert(title: "Could Not Load Audio", message: error.message)
            }
        }
    }

    private func presentError(_ title: String, _ error: ServerError) {
        errorAlert = ErrorAlert(title: title, message: ServerError.detailedMessage(from: error))
        statusMessage = nil
        activeJobId = nil
        isSubmitting = false
        isDrafting = false
        isRefining = false
        isSaving = false
    }
}
