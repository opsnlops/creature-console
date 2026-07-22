import AVFoundation
import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

struct AnimationTable: View {
    let eventLoop = EventLoop.shared

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1
    @AppStorage("animationFilmingCountdownSeconds") private var filmingCountdownSeconds: Int = 3

    let server = CreatureServerClient.shared
    let creatureManager = CreatureManager.shared

    var creature: Creature?

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \AnimationMetadataModel.title, order: .forward)
    private var animations: [AnimationMetadataModel]

    /// The cached sound list, used to flag animations whose sound file no longer exists on
    /// the server — silent bombs otherwise discovered only when playback fails mid-show.
    @Query private var sounds: [SoundModel]

    @State private var errorAlert: ErrorAlert?
    @State private var selection: AnimationIdentifier? = nil
    @State private var animationSoundToShare: String? = nil

    @State private var loadAnimationTask: Task<Void, Never>? = nil
    @State private var playAnimationTask: Task<Void, Never>? = nil
    @State private var interruptAnimationTask: Task<Void, Never>? = nil
    @State private var generateLipSyncTask: Task<Void, Never>? = nil

    @State private var navigateToEditor = false
    @State private var animationToEdit: Common.Animation? = nil
    @State private var scriptToEdit: DialogScript? = nil
    @State private var loadScriptTask: Task<Void, Never>? = nil
    @State private var generatingLipSyncForAnimation: AnimationIdentifier? = nil
    @State private var activeAnimationLipSyncJob:
        (animationId: AnimationIdentifier, jobId: String)? = nil
    @State private var observedJobInfo: JobStatusStore.JobInfo? = nil
    @State private var pendingDeleteAnimation: AnimationIdentifier? = nil
    @State private var showDeleteConfirmation = false
    @State private var deleteAnimationTask: Task<Void, Never>? = nil
    @State private var isDeletingAnimation = false
    @State private var showRenameSheet = false
    @State private var renameAnimationId: AnimationIdentifier? = nil
    @State private var renameAnimationTitle: String = ""
    @State private var renameOriginalTitle: String = ""
    @State private var renameAnimationTask: Task<Void, Never>? = nil
    @State private var isRenamingAnimation = false
    @State private var filmingPhase: FilmingPhase? = nil
    @State private var filmingFlowTask: Task<Void, Never>? = nil
    @State private var alignmentSoundDurationCache: TimeInterval? = nil

    /// Transient confirmation for successful actions (scheduling, rename, delete, lip sync).
    /// The server returns a detailed message ("Animation scheduled from frame X to Y") —
    /// showing it (with the universe) makes a successful-but-invisible schedule, like playing
    /// to a universe nothing listens on, immediately diagnosable instead of silent.
    @State private var statusBanner: String? = nil

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationTable")

    var body: some View {
        // Computed once per render, not per row — the row check is then O(1).
        let knownSoundFiles = Set(sounds.map(\.id))

        NavigationStack {
            VStack {
                if !animations.isEmpty {
                    Table(animations, selection: $selection) {
                        // No tap gestures on cell content — a gesture recognizer swallows
                        // mouse-downs and defeats the Table's native single-click selection.
                        // Row activation (double-click / tap) is the contextMenu's
                        // primaryAction below.
                        TableColumn("Name") { a in
                            HStack(spacing: 6) {
                                if let missing = missingSoundFile(for: a, known: knownSoundFiles) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .help(
                                            "References missing sound file “\(missing)” — playing this animation will fail."
                                        )
                                }
                                Text(a.title)
                            }
                        }
                        .width(min: 120, ideal: 250)
                        TableColumn("Frames") { a in
                            Text(a.numberOfFrames, format: .number)
                        }
                        .width(60)
                        TableColumn("Period") { a in
                            Text("\(a.millisecondsPerFrame)ms")
                        }
                        .width(55)
                        TableColumn("Audio") { a in
                            Text(a.soundFile)
                                .foregroundStyle(
                                    missingSoundFile(for: a, known: knownSoundFiles) != nil
                                        ? Color.orange : Color.primary)
                        }
                        TableColumn("Time (ms)") { a in
                            Text(a.numberOfFrames * a.millisecondsPerFrame, format: .number)
                        }
                        .width(80)
                    }
                    .contextMenu(forSelectionType: AnimationIdentifier.self) {
                        (items: Set<AnimationIdentifier>) in
                        let targetId = items.first ?? selection
                        // Determine if we have a selected ID (right-click updates selection automatically)
                        let hasSelection = targetId != nil

                        // The universe in the label makes the target visible *before* clicking —
                        // scheduling onto a universe nothing listens to succeeds silently on the
                        // server, and that mismatch has burned us (issue #28 testing).
                        Button {
                            playStoredAnimation(animationId: targetId)
                        } label: {
                            Label(
                                "Play on Server (Universe \(activeUniverse))", systemImage: "play")
                        }
                        .disabled(!hasSelection)

                        Button {
                            playAnimationForFilming(animationId: targetId)
                        } label: {
                            Label("Play Animation for Filming", systemImage: "video")
                        }
                        .disabled(!hasSelection || filmingPhase != nil || filmingFlowTask != nil)

                        Button {
                            interruptWithAnimation(animationId: targetId)
                        } label: {
                            Label(
                                "Interrupt & Play (Universe \(activeUniverse))",
                                systemImage: "bolt.fill")
                        }
                        .disabled(!hasSelection)

                        Button {
                            if let id = targetId {
                                loadAnimationForEditing(animationId: id)
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .disabled(!hasSelection)

                        // Jump to the source dialog script, but only when this animation was
                        // rendered from a saved one.
                        let sourceScriptId: DialogScriptIdentifier? = {
                            guard let id = targetId,
                                let md = animations.first(where: { $0.id == id })
                            else { return nil }
                            return md.sourceScriptIdentifier
                        }()
                        if let sourceScriptId {
                            Button {
                                loadScriptForEditing(scriptId: sourceScriptId)
                            } label: {
                                Label("Edit Script", systemImage: "text.bubble")
                            }
                        }

                        Button {
                            copyAnimationId(targetId)
                        } label: {
                            Label("Copy Animation ID", systemImage: "doc.on.doc")
                        }
                        .disabled(!hasSelection)

                        // The selected animation's sound file, for the share flow below.
                        let soundFileName: String = {
                            guard let id = targetId,
                                let md = animations.first(where: { $0.id == id })
                            else { return "" }
                            return md.soundFile
                        }()
                        ShareableSoundButton(
                            fileName: soundFileName,
                            title: "Generate Shareable Version of Sound…",
                            trigger: $animationSoundToShare)

                        let canGenerateLipSync: Bool = {
                            guard let id = targetId,
                                let md = animations.first(where: { $0.id == id })
                            else { return false }
                            return md.multitrackAudio
                        }()

                        Button {
                            if let id = targetId {
                                startAnimationLipSyncGeneration(animationId: id)
                            }
                        } label: {
                            Label("Create Lip Sync Data", systemImage: "waveform.badge.plus")
                        }
                        .disabled(
                            !canGenerateLipSync
                                || generatingLipSyncForAnimation != nil
                                || activeAnimationLipSyncJob != nil
                                || isDeletingAnimation
                                || isRenamingAnimation
                        )
                        Button {
                            if let id = targetId {
                                startAnimationRename(animationId: id)
                            }
                        } label: {
                            Label("Rename", systemImage: "pencil.and.outline")
                        }
                        .disabled(
                            targetId == nil
                                || isDeletingAnimation
                                || isRenamingAnimation
                        )
                        Divider()
                        Button(role: .destructive) {
                            if let id = targetId {
                                startAnimationDeletion(animationId: id)
                            }
                        } label: {
                            Label("Delete Animation", systemImage: "trash")
                        }
                        .disabled(targetId == nil || isDeletingAnimation || isRenamingAnimation)
                    } primaryAction: { items in
                        // Row activation: double-click on macOS, tap on iOS.
                        if let id = items.first ?? selection {
                            loadAnimationForEditing(animationId: id)
                        }
                    }
                    .shareableSoundFlow(fileName: $animationSoundToShare)
                } else {
                    ProgressView("Loading animations...")
                        .padding()
                }
            }  // VStack
            .onDisappear {
                loadAnimationTask?.cancel()
                playAnimationTask?.cancel()
                interruptAnimationTask?.cancel()
                generateLipSyncTask?.cancel()
                deleteAnimationTask?.cancel()
                renameAnimationTask?.cancel()
                loadScriptTask?.cancel()
                loadScriptTask = nil
                generateLipSyncTask = nil
                deleteAnimationTask = nil
                renameAnimationTask = nil
                filmingFlowTask?.cancel()
                activeAnimationLipSyncJob = nil
                generatingLipSyncForAnimation = nil
                isDeletingAnimation = false
                isRenamingAnimation = false
            }
            .onChange(of: selection) {
                logger.debug("selection is now \(String(describing: selection))")
            }
            .onChange(of: creature) {
                logger.debug("onChange() in AnimationTable")
            }
            .errorAlert($errorAlert, dismissLabel: "Fiiiiiine")
            .overlay {
                if let phase = filmingPhase {
                    FilmingCountdownOverlay(phase: phase, onCancel: cancelFilmingFlow)
                        .transition(.opacity)
                }
            }
            .statusBanner($statusBanner)
            .confirmationDialog(
                "Delete Animation?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    confirmAnimationDeletion()
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteAnimation = nil
                }
            } message: {
                if let id = pendingDeleteAnimation {
                    Text(
                        "This will permanently delete “\(animationTitle(for: id))” from the server."
                    )
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                RenameAnimationSheet(
                    title: $renameAnimationTitle,
                    originalTitle: renameOriginalTitle,
                    onCancel: cancelAnimationRename,
                    onSave: confirmAnimationRename
                )
                .frame(minWidth: 360)
            }
            .sheet(item: $scriptToEdit) { script in
                NavigationStack {
                    DialogScriptEditor(existing: script, mode: .animationLinked)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { scriptToEdit = nil }
                            }
                        }
                }
                #if os(macOS)
                    .frame(minWidth: 760, minHeight: 640)
                #endif
            }
            .navigationTitle("Animations")
            .bottomToolbarInset()
            #if os(macOS)
                .navigationSubtitle("Number of Animations: \(animations.count)")
            #endif
            .navigationDestination(isPresented: $navigateToEditor) {
                if let animation = animationToEdit {
                    AnimationEditor(animation: animation)
                } else {
                    // Fallback: if somehow no animation is loaded, present create-new
                    AnimationEditor(createNew: true)
                }
            }
            .toolbar(id: "animationTableToolbar") {
                ToolbarItem(id: "newTrack", placement: .primaryAction) {
                    NavigationLink(
                        destination: AnimationEditor(createNew: true),
                        label: {
                            Label("Add Track", systemImage: "plus")
                        }
                    )
                    .help("Create a new animation")
                }
            }
            .overlay {
                if isRenamingAnimation, let id = renameAnimationId {
                    ProcessingOverlayView(
                        message: "Renaming \(animationTitle(for: id))…",
                        progress: nil
                    )
                } else if isDeletingAnimation, let id = pendingDeleteAnimation {
                    ProcessingOverlayView(
                        message: "Deleting \(animationTitle(for: id))…",
                        progress: nil
                    )
                } else if let job = activeAnimationLipSyncJob {
                    ProcessingOverlayView(
                        message: animationOverlayMessage(
                            for: observedJobInfo,
                            animationId: job.animationId
                        ),
                        progress: observedJobInfo?.progressPercentage
                    )
                } else if let animationId = generatingLipSyncForAnimation {
                    ProcessingOverlayView(
                        message: "Submitting lip sync job for \(animationTitle(for: animationId))…",
                        progress: nil
                    )
                }
            }
            .animation(
                .default,
                value: activeAnimationLipSyncJob != nil || generatingLipSyncForAnimation != nil
                    || isDeletingAnimation || isRenamingAnimation
            )
            .watchJob(activeAnimationLipSyncJob?.jobId) { info in
                observedJobInfo = info
            } onTerminal: { info in
                observedJobInfo = info
                if let animationId = activeAnimationLipSyncJob?.animationId {
                    handleAnimationJobCompletion(info: info, animationId: animationId)
                } else {
                    finalizeAnimationJob()
                }
            } onRemoved: {
                finalizeAnimationJob()
            }
        }  // NavigationStack
    }  // body

    private func startAnimationLipSyncGeneration(animationId: AnimationIdentifier) {
        guard generatingLipSyncForAnimation == nil && activeAnimationLipSyncJob == nil else {
            logger.debug("Lip sync generation already in progress; ignoring request")
            return
        }

        logger.debug("Starting lip sync generation for animation \(animationId)")
        generatingLipSyncForAnimation = animationId
        activeAnimationLipSyncJob = nil

        generateLipSyncTask?.cancel()
        generateLipSyncTask = Task {
            await performAnimationLipSyncGeneration(animationId: animationId)
        }
    }

    private func performAnimationLipSyncGeneration(animationId: AnimationIdentifier) async {
        let result = await server.generateLipSyncForAnimation(animationId: animationId)

        if Task.isCancelled {
            generatingLipSyncForAnimation = nil
            activeAnimationLipSyncJob = nil
            generateLipSyncTask = nil
            logger.debug("Lip sync generation task for \(animationId) was cancelled")
            return
        }

        switch result {
        case .success(let job):
            logger.debug(
                "Animation lip sync job queued: \(job.jobId) for animation \(animationId) (\(job.jobType.rawValue))"
            )
            await JobStatusStore.shared.seedQueued(
                job, details: AnimationLipSyncJobDetails(animationId: animationId))

            activeAnimationLipSyncJob = (animationId, job.jobId)
            generatingLipSyncForAnimation = animationId
            observedJobInfo = nil

        case .failure(let error):
            logger.error("Failed to queue lip sync generation: \(error.localizedDescription)")
            errorAlert = ErrorAlert(title: "Lip Sync Generation Failed", error: error)
            generatingLipSyncForAnimation = nil
            activeAnimationLipSyncJob = nil
        }

        generateLipSyncTask = nil
    }

    private func startAnimationRename(animationId: AnimationIdentifier) {
        guard !isRenamingAnimation else { return }
        renameAnimationId = animationId
        let currentTitle = animationTitle(for: animationId)
        renameOriginalTitle = currentTitle
        renameAnimationTitle = currentTitle
        showRenameSheet = true
    }

    private func cancelAnimationRename() {
        renameAnimationTask?.cancel()
        renameAnimationTask = nil
        showRenameSheet = false
        renameAnimationTitle = ""
        renameOriginalTitle = ""
        renameAnimationId = nil
    }

    private func confirmAnimationRename() {
        guard let animationId = renameAnimationId else { return }
        let trimmed = renameAnimationTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorAlert = ErrorAlert(
                title: "Invalid Name", message: "Animation name cannot be empty.")
            return
        }

        if trimmed == renameOriginalTitle {
            cancelAnimationRename()
            return
        }

        renameAnimationTask?.cancel()
        isRenamingAnimation = true
        showRenameSheet = false

        renameAnimationTask = Task {
            await performAnimationRename(animationId: animationId, newTitle: trimmed)
        }
    }

    private func performAnimationRename(animationId: AnimationIdentifier, newTitle: String) async {
        let fetchResult = await server.getAnimation(animationId: animationId)

        switch fetchResult {
        case .success(var fetchedAnimation):
            fetchedAnimation.metadata.title = newTitle
            let saveResult = await server.saveAnimation(animation: fetchedAnimation)
            switch saveResult {
            case .success:
                if let model = animations.first(where: { $0.id == animationId }) {
                    model.title = newTitle
                    do {
                        try modelContext.save()
                    } catch {
                        logger.warning(
                            "Unable to persist renamed animation locally: \(error.localizedDescription)"
                        )
                    }
                }
                statusBanner = "Renamed animation to \(newTitle)."
            case .failure(let error):
                let message = ServerError.detailedMessage(from: error)
                logger.warning("Unable to save renamed animation: \(message)")
                errorAlert = ErrorAlert(title: "Unable to Rename Animation", message: message)
            }

        case .failure(let error):
            let message = ServerError.detailedMessage(from: error)
            logger.warning("Unable to load animation before rename: \(message)")
            errorAlert = ErrorAlert(title: "Unable to Rename Animation", message: message)
        }

        isRenamingAnimation = false
        renameAnimationTask = nil
        renameAnimationId = nil
        renameAnimationTitle = ""
        renameOriginalTitle = ""
    }

    private func startAnimationDeletion(animationId: AnimationIdentifier) {
        pendingDeleteAnimation = animationId
        showDeleteConfirmation = true
    }

    private func confirmAnimationDeletion() {
        guard let animationId = pendingDeleteAnimation, !isDeletingAnimation else { return }

        deleteAnimationTask?.cancel()
        isDeletingAnimation = true

        deleteAnimationTask = Task {
            await performAnimationDeletion(animationId: animationId)
        }
    }

    private func performAnimationDeletion(animationId: AnimationIdentifier) async {
        let result = await server.deleteAnimation(animationId: animationId)

        isDeletingAnimation = false
        showDeleteConfirmation = false

        switch result {
        case .success:
            // Grab the title before the model leaves the cache, so the banner names the
            // animation instead of falling back to its raw identifier.
            let deletedTitle = animationTitle(for: animationId)
            if let model = animations.first(where: { $0.id == animationId }) {
                modelContext.delete(model)
                do {
                    try modelContext.save()
                } catch {
                    logger.warning(
                        "Unable to persist deletion locally: \(error.localizedDescription)")
                }
            }
            pendingDeleteAnimation = nil
            statusBanner = "Deleted \(deletedTitle)."
        case .failure(let error):
            let message = ServerError.detailedMessage(from: error)
            logger.warning("Unable to delete animation \(animationId): \(message)")
            pendingDeleteAnimation = nil
            errorAlert = ErrorAlert(title: "Unable to Delete Animation", message: message)
        }

        deleteAnimationTask = nil
    }

    private func animationOverlayMessage(
        for info: JobStatusStore.JobInfo?,
        animationId: AnimationIdentifier
    ) -> String {
        guard let info else {
            return "Submitting lip sync job for \(animationTitle(for: animationId))…"
        }

        let targetId = info.animationLipSyncDetails?.animationId ?? animationId
        let displayName = animationTitle(for: targetId)

        switch info.status {
        case .queued:
            return "Lip sync job queued for \(displayName)…"
        case .running:
            return "Generating lip sync for \(displayName)…"
        case .completed:
            return "Lip sync completed for \(displayName)"
        case .failed:
            return "Lip sync failed for \(displayName)"
        case .unknown:
            return "Processing lip sync job for \(displayName)…"
        }
    }

    private func animationTitle(for animationId: AnimationIdentifier) -> String {
        animations.first(where: { $0.id == animationId })?.title ?? animationId
    }

    /// Fetch the source dialog script and present it in a sheet. The pointer is soft (the
    /// script may have been deleted), so surface a friendly message on 404.
    private func loadScriptForEditing(scriptId: DialogScriptIdentifier) {
        loadScriptTask?.cancel()
        loadScriptTask = Task {
            let result = await server.getDialogScript(id: scriptId)
            switch result {
            case .success(let script):
                scriptToEdit = script
            case .failure(.notFound):
                errorAlert = ErrorAlert(
                    title: "Dialog Script Not Found",
                    message:
                        "The source dialog script no longer exists — it may have been deleted. The animation still plays from its rendered snapshot."
                )
            case .failure(let error):
                errorAlert = ErrorAlert(title: "Unable to Open Dialog Script", error: error)
            }
        }
    }

    private func copyAnimationId(_ animationId: AnimationIdentifier?) {
        guard let animationId else { return }
        Pasteboard.copy(animationId)
    }

    @MainActor
    private func handleAnimationJobCompletion(
        info: JobStatusStore.JobInfo,
        animationId: AnimationIdentifier
    ) {
        let targetId = info.animationLipSyncDetails?.animationId ?? animationId
        let displayName = animationTitle(for: targetId)

        switch info.status {
        case .completed:
            if let result = info.animationLipSyncResult {
                let trackDescription =
                    result.updatedTracks == 1
                    ? "1 track"
                    : "\(result.updatedTracks) tracks"
                statusBanner =
                    "Lip sync data for \(displayName) finished processing. \(trackDescription) updated."
            } else {
                statusBanner = "Lip sync data for \(displayName) finished processing."
            }
        case .failed:
            let message =
                info.result?.isEmpty == false
                ? info.result!
                : "The server could not generate lip sync for \(displayName)."
            errorAlert = ErrorAlert(title: "Lip Sync Failed", message: message)
        default:
            break
        }

        finalizeAnimationJob()
    }

    @MainActor
    private func finalizeAnimationJob() {
        generatingLipSyncForAnimation = nil
        activeAnimationLipSyncJob = nil
        observedJobInfo = nil
    }

    func loadAnimationForEditing(animationId: AnimationIdentifier) {
        loadAnimationTask?.cancel()

        loadAnimationTask = Task {
            let result = await server.getAnimation(animationId: animationId)
            switch result {
            case .success(let animation):
                animationToEdit = animation
                navigateToEditor = true
            case .failure(let error):
                let message = "Error: \(error.localizedDescription)"
                logger.warning("Unable to load animation for editing: \(message)")
                errorAlert = ErrorAlert(title: "Unable to Load Animation", message: message)
            }
        }
    }

    func playStoredAnimation(animationId: AnimationIdentifier?) {
        guard let animationId = animationId else {
            logger.debug("playStoredAnimation was called with a nil selection")
            return
        }

        scheduleAnimationPlayback(animationId: animationId)
    }

    @MainActor
    private func scheduleAnimationPlayback(animationId: AnimationIdentifier) {
        playAnimationTask?.cancel()
        playAnimationTask = makePlayAnimationTask(animationId: animationId)
    }

    private func makePlayAnimationTask(animationId: AnimationIdentifier) -> Task<Void, Never> {
        let manager = creatureManager
        let universe = activeUniverse

        return Task {
            let result = await manager.playStoredAnimationOnServer(
                animationId: animationId, universe: universe)
            switch result {
            case .success(let message):
                logger.debug("Animation Scheduled: \(message)")
                statusBanner = "Universe \(universe): \(message)"
            case .failure(let error):
                let message = ServerError.detailedMessage(from: error)
                logger.warning("Unable to schedule animation: \(message)")
                errorAlert = ErrorAlert(title: "Unable to Schedule Animation", message: message)
            }
        }
    }

    @MainActor
    func playAnimationForFilming(animationId: AnimationIdentifier?) {
        guard let animationId = animationId else {
            logger.debug("playAnimationForFilming was called with a nil selection")
            return
        }

        logger.debug("Starting filming countdown flow for animation \(animationId)")
        filmingFlowTask?.cancel()

        let countdownSeconds = max(0, filmingCountdownSeconds)
        filmingFlowTask = Task {
            await performFilmingCountdownFlow(
                animationId: animationId, countdownSeconds: countdownSeconds)
        }
    }

    /// The animation's referenced-but-missing sound file, or `nil` when it's fine. An empty
    /// `soundFile` means "no audio" (fine), and an empty sound cache means we can't judge —
    /// absence of the cache isn't evidence a file is missing, so nothing gets flagged.
    ///
    /// Membership is judged on the **basename**: the server's sound list emits basenames even
    /// for files in subdirectories (dialog renders live under `dialog/` but list as
    /// `<uuid>.wav`), and its resolver plays them back by basename too — so an animation
    /// referencing `dialog/<uuid>.wav` is fine when `<uuid>.wav` is in the store.
    private func missingSoundFile(for animation: AnimationMetadataModel, known: Set<String>)
        -> String?
    {
        guard !animation.soundFile.isEmpty, !known.isEmpty else { return nil }
        let basename = animation.soundFile.split(separator: "/").last.map(String.init) ?? ""
        guard !basename.isEmpty, !known.contains(basename) else { return nil }
        return animation.soundFile
    }

    @MainActor
    private func presentAudioPlaybackError(_ error: AudioError) {
        errorAlert = ErrorAlert(
            title: "Unable to Play Alignment Sound", message: audioErrorMessage(for: error))
    }

    private func audioErrorMessage(for error: AudioError) -> String {
        switch error {
        case .fileNotFound(let message),
            .noAccess(let message),
            .systemError(let message),
            .failedToLoad(let message):
            return message
        }
    }

    @MainActor
    private func loadAlignmentSoundDuration() async -> TimeInterval? {
        if let cached = alignmentSoundDurationCache {
            return cached
        }

        guard
            let url = Bundle.main.url(
                forResource: "animationAlignmentSound", withExtension: "flac")
        else {
            logger.warning("Alignment sound asset not found in bundle")
            return nil
        }

        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else {
                logger.warning("Alignment sound duration is not usable: \(seconds)")
                return nil
            }

            alignmentSoundDurationCache = seconds
            return seconds
        } catch {
            logger.warning("Failed to load alignment sound duration: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private func cancelFilmingFlow() {
        guard filmingPhase != nil || filmingFlowTask != nil else { return }
        logger.debug("Cancelling filming countdown flow")
        filmingFlowTask?.cancel()
        filmingFlowTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            filmingPhase = nil
        }
        Task {
            await AppState.shared.setCurrentActivity(.idle)
        }
    }

    @MainActor
    private func performFilmingCountdownFlow(
        animationId: AnimationIdentifier, countdownSeconds: Int
    ) async {
        await AppState.shared.setCurrentActivity(.countingDownForFilming)
        defer {
            Task { await AppState.shared.setCurrentActivity(.idle) }
            withAnimation(.easeInOut(duration: 0.2)) {
                filmingPhase = nil
            }
            filmingFlowTask = nil
        }

        do {
            if countdownSeconds > 0 {
                for remaining in stride(from: countdownSeconds, through: 1, by: -1) {
                    try Task.checkCancellation()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filmingPhase = .countdown(secondsRemaining: remaining)
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    filmingPhase = .countdown(secondsRemaining: 0)
                }
                try await Task.sleep(nanoseconds: 300_000_000)
            }

            try Task.checkCancellation()
            withAnimation(.easeInOut(duration: 0.2)) {
                filmingPhase = .playingCue
            }

            let cueDuration = await loadAlignmentSoundDuration() ?? 2.0
            let audioResult = AudioManager.shared.playBundledSound(
                name: "animationAlignmentSound", extension: "flac")

            switch audioResult {
            case .success:
                break
            case .failure(let audioError):
                logger.warning(
                    "Alignment sound playback failed: \(audioErrorMessage(for: audioError))")
                presentAudioPlaybackError(audioError)
                return
            }

            let waitNanoseconds = UInt64(max(cueDuration, 0.0) * 1_000_000_000)
            if waitNanoseconds > 0 {
                try await Task.sleep(nanoseconds: waitNanoseconds)
            }

            try Task.checkCancellation()
            withAnimation(.easeInOut(duration: 0.2)) {
                filmingPhase = nil
            }
            scheduleAnimationPlayback(animationId: animationId)
        } catch is CancellationError {
            logger.debug("Filming countdown cancelled")
        } catch {
            logger.error("Filming countdown flow failed: \(error.localizedDescription)")
            presentAudioPlaybackError(
                .systemError("Filming countdown failed: \(error.localizedDescription)"))
        }
    }


    func interruptWithAnimation(animationId: AnimationIdentifier?) {
        guard let animationId = animationId else {
            logger.debug("interruptWithAnimation was called with a nil selection")
            return
        }

        interruptAnimationTask?.cancel()

        let manager = creatureManager
        let universe = activeUniverse

        interruptAnimationTask = Task {
            let result = await manager.interruptWithAnimation(
                animationId: animationId, universe: universe, resumePlaylist: true)
            switch result {
            case .success(let message):
                logger.debug("Animation Interrupt Scheduled: \(message)")
                statusBanner = "Universe \(universe): \(message)"
            case .failure(let error):
                let message = ServerError.detailedMessage(from: error)
                logger.warning("Unable to schedule animation interrupt: \(message)")
                errorAlert = ErrorAlert(title: "Unable to Interrupt Animation", message: message)
            }
        }
    }
}

#Preview {
    AnimationTable(creature: .mock())
}
