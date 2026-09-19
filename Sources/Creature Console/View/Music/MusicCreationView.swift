import AVFoundation
import Common
import Foundation
import OSLog
import SwiftUI

/// The music composer. Describe a piece and let the server plan it, or own the plan section by
/// section; generate takes, listen to them against the dialog, and build the next take on the
/// last one — keep its opening, sound like it, edit its plan — until it's right. Then accept it
/// for the final render.
///
/// Music is deliberately downstream of a saved, full-dialog voice take (see `MusicSubject`).
/// Candidates live in session state so experimentation is cheap; promotion is the explicit
/// commit point. The same view is embedded by the dialog editor and shown by the sidebar's
/// Music workspace.
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

    private enum ComposerMode: String, CaseIterable, Identifiable {
        case describe
        case plan
        var id: String { rawValue }
    }

    // Composer
    @State private var composerMode: ComposerMode = .describe
    @State private var prompt = ""
    @State private var generationMode: DialogMusicGenerationMode = .track
    @State private var durationExtensionSeconds = 0.0
    @State private var allowVocals = false
    @State private var finetune: MusicFinetuneSelection?
    @State private var seedText = ""
    @State private var plan = MusicCompositionPlan(chunks: [])
    /// The take the current plan builds on, for section labels and "sound like" defaults.
    @State private var referenceTake: MusicReferenceTake?
    /// Learned from the first plan draft or candidate; the plan must cover it.
    @State private var dialogDurationMilliseconds: Int64?
    @State private var isDrafting = false

    // Generation
    @State private var candidates: [DialogMusicCandidate] = []
    @State private var nextOrdinal = 1
    @State private var activeJobId: String?
    @State private var observedJob: JobStatusStore.JobInfo?
    @State private var jobSourceVoice: DialogAcceptedVoice?
    @State private var isSubmitting = false

    // Keep-the-opening sheet
    @State private var keepSource: MusicReferenceTake?
    @State private var keepSeconds = 0.0

    // Listening
    @State private var isAuditioning = false
    @State private var musicVolume = 0.35
    @State private var auditionToken = UUID()
    @State private var musicPlaybackToken = UUID()
    @State private var isPlayingAcceptedMusic = false

    // Promotion / feedback
    @State private var candidateToPromote: DialogMusicCandidate?
    @State private var showReplacementConfirmation = false
    @State private var showClearConfirmation = false
    @State private var soundToShare: String?
    @State private var statusMessage: String?
    @State private var errorAlert: ErrorAlert?

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var promptIsValid: Bool {
        !trimmedPrompt.isEmpty && trimmedPrompt.utf8.count <= DialogLimits.maxMusicPromptBytes
    }

    private var isBusy: Bool {
        isSubmitting || isDrafting || (observedJob.map { !$0.isTerminal } ?? false)
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

    private var planProblems: [String] {
        plan.validationProblems(dialogDurationMilliseconds: dialogDurationMilliseconds)
    }

    private var canGenerate: Bool {
        guard subject.canCompose, !isBusy else { return false }
        switch composerMode {
        case .describe: return promptIsValid
        case .plan: return planProblems.isEmpty && seedIsValid
        }
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

            composer

            if let reason = subject.unavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    generate()
                } label: {
                    Label("Generate Take", systemImage: "music.note.list")
                }
                .buttonStyle(.glassProminent)
                .disabled(!canGenerate)

                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Takes").font(.headline)
                    ForEach(candidates) { candidate in
                        MusicCandidateCard(
                            candidate: candidate,
                            isCurrent: candidate.matches(subject.acceptedVoice),
                            isAccepted: subject.backgroundMusic?.generationId == candidate.id,
                            hasAcceptedMusic: subject.backgroundMusic != nil,
                            canPromote: !subject.hasUnsavedChanges,
                            isAuditioning: isAuditioning,
                            onAudition: { audition(candidate) },
                            onPromote: { requestPromotion(candidate) },
                            onEditPlan: { reference, recipe in
                                load(recipe: recipe, from: reference)
                            },
                            onKeepOpening: { reference in beginKeepingOpening(of: reference) },
                            onSoundLike: { reference in soundLike(reference) })
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
        .onChange(of: subject.acceptedVoice) { _, _ in
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
        .sheet(item: $keepSource) { source in
            keepOpeningSheet(source)
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

    // MARK: - Composer

    @ViewBuilder
    private var composer: some View {
        Picker("Compose by", selection: $composerMode) {
            Text("Describe").tag(ComposerMode.describe)
            Text("Plan").tag(ComposerMode.plan)
        }
        .pickerStyle(.segmented)

        switch composerMode {
        case .describe:
            describeComposer
        case .plan:
            planComposer
        }

        commonControls
    }

    @ViewBuilder
    private var describeComposer: some View {
        TextField(
            "Describe the score, mood, instruments, and pacing…", text: $prompt,
            axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...5)
        HStack {
            Button {
                draftPlan(from: nil)
            } label: {
                Label("Draft a Plan", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.glass)
            .disabled(!subject.canCompose || !promptIsValid || isBusy)
            .help(
                "Ask the server to turn this description into an editable, section-by-section plan sized to the dialog"
            )
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
    }

    @ViewBuilder
    private var planComposer: some View {
        if plan.chunks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "A plan is the piece section by section: what each part sounds like, how long it runs, and what it should lean into or avoid. Draft one from a description, start from a take's plan, or build it by hand."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Button {
                        composerMode = .describe
                    } label: {
                        Label("Describe It First", systemImage: "text.quote")
                    }
                    .buttonStyle(.glass)
                    Button {
                        plan = MusicCompositionPlan(chunks: [
                            .generation(
                                MusicGenerationChunk(
                                    text: "",
                                    durationMilliseconds: dialogDurationMilliseconds ?? 30_000))
                        ])
                    } label: {
                        Label("Start Empty", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                }
            }
        } else {
            if let referenceTake {
                HStack(spacing: 8) {
                    Label(
                        "Building on \(referenceTake.label)", systemImage: "arrow.turn.down.right"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    if referenceTake.plan != nil {
                        Button("Keep the Opening…") { beginKeepingOpening(of: referenceTake) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    Button("Sound Like It") { soundLike(referenceTake) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    if plan.chunks.contains(where: {
                        if case .generation(let chunk) = $0 {
                            return chunk.conditioningReference != nil
                        }
                        return false
                    }) {
                        Button("Stop Sounding Like It") { plan = plan.unconditioned() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
            MusicPlanEditor(
                plan: $plan, dialogDurationMilliseconds: dialogDurationMilliseconds,
                referenceTake: referenceTake)
            HStack {
                TextField("Redraft this plan from a description…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                Button {
                    draftPlan(from: plan)
                } label: {
                    Label("Redraft", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .disabled(!subject.canCompose || !promptIsValid || isBusy)
                .help(
                    "Ask the server for a fresh plan from this description, starting from the current one"
                )
            }
            HStack {
                Text("Seed")
                TextField("random", text: $seedText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                if !seedIsValid {
                    Text("0–\(DialogLimits.maxMusicSeed)")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Reuse a seed to keep tweaks consistent between takes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Plan", role: .destructive) {
                    plan = MusicCompositionPlan(chunks: [])
                    referenceTake = nil
                    seedText = ""
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .font(.caption)
        }
    }

    /// Always Music 2.5: there is no reason left to reach for Music 2. The recipe still names
    /// the model an older take was made with.
    @ViewBuilder
    private var commonControls: some View {
        MusicFinetunePicker(selection: $finetune)
            .font(.callout)
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
            Text(music.prompt.isEmpty ? "Composed from a plan" : music.prompt)
                .font(.subheadline)

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
                Button(isPlayingAcceptedMusic ? "Stop Music" : "Play Music") {
                    if isPlayingAcceptedMusic {
                        stopAcceptedMusic()
                    } else {
                        playAcceptedMusic(music)
                    }
                }
                .disabled(isAuditioning)
                Button("Share MP3…") { soundToShare = music.soundFile }
                Button {
                    openRecipe(of: music)
                } label: {
                    Label("Open Recipe", systemImage: "slider.horizontal.3")
                }
                .help("Load how this music was made into the composer, to iterate on it")
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

    // MARK: - Keep the opening

    @ViewBuilder
    private func keepOpeningSheet(_ source: MusicReferenceTake) -> some View {
        let minimum = Double(DialogLimits.minMusicChunkMilliseconds) / 1_000
        let maximum = max(minimum, Double(source.durationMilliseconds) / 1_000 - minimum)
        let candidatePlan = source.plan?.keepingOpening(
            upTo: Int64((keepSeconds * 1_000).rounded()), of: source.songId)
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep the opening of \(source.label)").font(.title3.bold())
            Text(
                "Everything up to this point is re-rendered from \(source.label); the rest is composed fresh from the same plan, which you can edit before generating. The kept part comes out close to the original, not sample-exact."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Text("Keep the first")
                Slider(value: $keepSeconds, in: minimum...maximum, step: 0.5)
                Text(TimeHelper.formatDuration(keepSeconds))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            if candidatePlan == nil {
                Label(
                    "That point would leave a section shorter than \(Int(minimum)) seconds. Move it a little.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else if let candidatePlan {
                Text(
                    "\(candidatePlan.chunks.filter(\.isAudioReference).count) reference section(s), \(candidatePlan.chunks.count - candidatePlan.chunks.filter(\.isAudioReference).count) to compose."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { keepSource = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Use This Plan") {
                    if let candidatePlan {
                        plan = candidatePlan
                        referenceTake = source
                        composerMode = .plan
                        statusMessage =
                            "Kept the first \(TimeHelper.formatDuration(keepSeconds)) of \(source.label). Edit the rest and generate."
                    }
                    keepSource = nil
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(candidatePlan == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 460)
    }

    private func beginKeepingOpening(of reference: MusicReferenceTake) {
        guard reference.plan != nil else { return }
        keepSeconds = min(
            max(Double(DialogLimits.minMusicChunkMilliseconds) / 1_000, 8),
            Double(reference.durationMilliseconds) / 1_000 / 2)
        keepSource = reference
    }

    /// Put a conditioning reference to `reference` on every composed section. Without a plan
    /// yet, drafts one from the description first, then conditions it.
    private func soundLike(_ reference: MusicReferenceTake) {
        referenceTake = reference
        if plan.chunks.isEmpty {
            if let sourcePlan = reference.plan {
                plan = sourcePlan.conditioned(on: reference.conditioningSpan, strength: .medium)
                composerMode = .plan
                statusMessage = "Every section will sound like \(reference.label)."
            } else if promptIsValid {
                draftPlan(from: nil) { drafted in
                    drafted.conditioned(on: reference.conditioningSpan, strength: .medium)
                }
            } else {
                composerMode = .describe
                statusMessage =
                    "Describe the piece first, then it can sound like \(reference.label)."
            }
            return
        }
        plan = plan.conditioned(on: reference.conditioningSpan, strength: .medium)
        composerMode = .plan
        statusMessage = "Every section will sound like \(reference.label)."
    }

    /// Load a take's recipe into the composer so the next take starts where this one ended.
    private func load(recipe: DialogMusicRecipe, from reference: MusicReferenceTake) {
        finetune = recipe.finetune
        if let seed = recipe.seed { seedText = String(seed) }
        if let recipePrompt = recipe.prompt { prompt = recipePrompt }
        if let mode = recipe.generationMode { generationMode = mode }
        if let instrumental = recipe.forceInstrumental { allowVocals = !instrumental }
        if let sourcePlan = recipe.compositionPlan {
            plan = sourcePlan
            referenceTake = reference
            composerMode = .plan
            statusMessage = "Loaded the plan from \(reference.label)."
        } else {
            composerMode = .describe
            statusMessage = "Loaded the description from \(reference.label)."
        }
    }

    private func openRecipe(of music: DialogBackgroundMusic) {
        isDrafting = true
        statusMessage = "Reading how the accepted music was made…"
        Task {
            let result = await server.getDialogMusicRecipe(generationId: music.generationId)
            await MainActor.run {
                isDrafting = false
                switch result {
                case .success(let recipe):
                    let duration = recipe.compositionPlan?.totalDurationMilliseconds ?? 0
                    let reference = MusicReferenceTake(
                        label: "the accepted music", songId: recipe.songId,
                        durationMilliseconds: duration, plan: recipe.compositionPlan)
                    load(recipe: recipe, from: reference)
                    // Only a take ElevenLabs kept can be referenced by the next one.
                    if !recipe.canBeReferenced {
                        referenceTake = nil
                    }
                case .failure(.notFound):
                    errorAlert = ErrorAlert(
                        title: "Recipe Unavailable",
                        message:
                            "The server no longer has this take's recipe: it aged out of the candidate cache. Compose a new take instead."
                    )
                    statusMessage = nil
                case .failure(let error):
                    presentError("Could Not Read Recipe", error)
                }
            }
        }
    }

    // MARK: - Drafting and generating

    /// Ask the server for a plan from the description, sized to the accepted take. `source`
    /// seeds the draft; `transform` adjusts the result before it lands in the editor.
    private func draftPlan(
        from source: MusicCompositionPlan?,
        transform: @escaping @Sendable (MusicCompositionPlan) -> MusicCompositionPlan = { $0 }
    ) {
        guard let voice = subject.acceptedVoice, subject.canCompose, promptIsValid else { return }
        isDrafting = true
        statusMessage = "Drafting a plan…"
        let request = DialogMusicPlanRequest(
            dialogCacheKey: voice.dialogCacheKey,
            dialogGenerationId: voice.generationId,
            prompt: trimmedPrompt,
            durationExtensionMilliseconds: Int64(durationExtensionSeconds * 1_000),
            sourceCompositionPlan: source)
        Task {
            let result = await server.draftDialogMusicPlan(request)
            await MainActor.run {
                isDrafting = false
                switch result {
                case .success(let drafted):
                    dialogDurationMilliseconds = drafted.dialogDurationMilliseconds
                    plan = transform(drafted.compositionPlan)
                    if source == nil { referenceTake = nil }
                    composerMode = .plan
                    statusMessage =
                        "Drafted \(drafted.compositionPlan.chunks.count) section(s) over \(TimeHelper.formatDuration(Double(drafted.musicLengthMilliseconds) / 1_000)). Edit, then generate."
                case .failure(let error):
                    presentError("Could Not Draft a Plan", error)
                }
            }
        }
    }

    private func generate() {
        guard let scriptId = subject.scriptId, let voice = subject.acceptedVoice, canGenerate
        else { return }
        let composition: DialogMusicRequest.Composition
        switch composerMode {
        case .describe:
            composition = .prompt(
                DialogMusicRequest.Prompt(
                    prompt: trimmedPrompt,
                    durationExtensionMilliseconds: Int64(durationExtensionSeconds * 1_000),
                    generationMode: generationMode,
                    forceInstrumental: !allowVocals))
        case .plan:
            composition = .plan(plan, seed: seed)
        }
        let request = DialogMusicRequest(
            scriptId: scriptId,
            dialogCacheKey: voice.dialogCacheKey,
            dialogGenerationId: voice.generationId,
            composition: composition,
            finetune: finetune)
        isSubmitting = true
        jobSourceVoice = voice
        statusMessage = "Starting music generation…"
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
            sourceDialogGenerationId: sourceVoice.generationId, ordinal: nextOrdinal)
        nextOrdinal += 1
        dialogDurationMilliseconds = result.dialogDurationMilliseconds
        candidates.insert(candidate, at: 0)
        statusMessage = "\(candidate.label) ready"
        audition(candidate)
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

    // MARK: - Listening

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
                        cacheKey: "accepted-music-\(music.generationId.uuidString.lowercased())",
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

    private func audition(voice: DialogAcceptedVoice, musicURL: URL, candidateId: UUID?) {
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
        isDrafting = false
    }
}
