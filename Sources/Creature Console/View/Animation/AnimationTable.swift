import AVFoundation
import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

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

    @State private var showErrorAlert = false
    @State private var alertTitle = "Unable to load Animations"
    @State private var alertMessage = ""
    @State private var selection: AnimationIdentifier? = nil

    @State private var loadAnimationTask: Task<Void, Never>? = nil
    @State private var playAnimationTask: Task<Void, Never>? = nil
    @State private var interruptAnimationTask: Task<Void, Never>? = nil
    @State private var generateLipSyncTask: Task<Void, Never>? = nil

    @State private var navigateToEditor = false
    @State private var animationToEdit: Common.Animation? = nil
    @State private var generatingLipSyncForAnimation: AnimationIdentifier? = nil
    @State private var activeAnimationLipSyncJob:
        (animationId: AnimationIdentifier, jobId: String)? = nil
    @State private var observedJobInfo: JobStatusStore.JobInfo? = nil
    @State private var jobEventsTask: Task<Void, Never>? = nil
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

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationTable")

    var body: some View {
        NavigationStack {
            VStack {
                if !animations.isEmpty {
                    Table(animations, selection: $selection) {
                        TableColumn("Name") { a in
                            Text(a.title)
                                .onTapGesture(count: 2) {
                                    loadAnimationForEditing(animationId: a.id)
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

                        Button {
                            playStoredAnimation(animationId: targetId)
                        } label: {
                            Label("Play on Server", systemImage: "play")
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
                            Label("Interrupt & Play", systemImage: "bolt.fill")
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

                        // Sound file action (kept as a stub; disabled when no sound file)
                        let hasSound: Bool = {
                            guard let id = targetId,
                                let md = animations.first(where: { $0.id == id })
                            else { return false }
                            return !md.soundFile.isEmpty
                        }()
                        Button {
                            print("play sound file selected")
                        } label: {
                            Label("Play Sound File", systemImage: "music.quarternote.3")
                        }
                        .disabled(!hasSound)

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
                    }
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
                jobEventsTask?.cancel()
                deleteAnimationTask?.cancel()
                renameAnimationTask?.cancel()
                generateLipSyncTask = nil
                jobEventsTask = nil
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
                logger.info("onChange() in AnimationTable")
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("Fiiiiiine")) {
                        alertTitle = "Unable to load Animations"
                    }
                )
            }
            .overlay {
                if let phase = filmingPhase {
                    FilmingCountdownOverlay(phase: phase, onCancel: cancelFilmingFlow)
                        .transition(.opacity)
                }
            }
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
            .navigationTitle("Animations")
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
            .task(id: activeAnimationLipSyncJob?.jobId) {
                jobEventsTask?.cancel()
                observedJobInfo = nil

                guard let job = activeAnimationLipSyncJob else { return }
                jobEventsTask = Task {
                    let stream = await JobStatusStore.shared.events()
                    for await event in stream {
                        switch event {
                        case .updated(let info) where info.jobId == job.jobId:
                            await MainActor.run {
                                observedJobInfo = info
                                if info.isTerminal {
                                    handleAnimationJobCompletion(
                                        info: info, animationId: job.animationId)
                                }
                            }
                            if info.isTerminal {
                                await JobStatusStore.shared.remove(jobId: job.jobId)
                                return
                            }
                        case .removed(let removedId) where removedId == job.jobId:
                            await MainActor.run {
                                finalizeAnimationJob()
                            }
                            return
                        default:
                            continue
                        }
                    }
                }
            }
        }  // NavigationStack
    }  // body

    private func startAnimationLipSyncGeneration(animationId: AnimationIdentifier) {
        guard generatingLipSyncForAnimation == nil && activeAnimationLipSyncJob == nil else {
            logger.debug("Lip sync generation already in progress; ignoring request")
            return
        }

        logger.info("Starting lip sync generation for animation \(animationId)")
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
            await MainActor.run {
                generatingLipSyncForAnimation = nil
                activeAnimationLipSyncJob = nil
                generateLipSyncTask = nil
            }
            logger.debug("Lip sync generation task for \(animationId) was cancelled")
            return
        }

        switch result {
        case .success(let job):
            logger.info(
                "Animation lip sync job queued: \(job.jobId) for animation \(animationId) (\(job.jobType.rawValue))"
            )
            if let data = try? JSONEncoder().encode(
                AnimationLipSyncJobDetails(animationId: animationId)),
                let detailsString = String(data: data, encoding: .utf8)
            {
                let seeded = JobProgress(
                    jobId: job.jobId,
                    jobType: job.jobType,
                    status: .queued,
                    progress: 0.0,
                    details: detailsString
                )
                await JobStatusStore.shared.update(with: seeded)
            }

            await MainActor.run {
                activeAnimationLipSyncJob = (animationId, job.jobId)
                generatingLipSyncForAnimation = animationId
                observedJobInfo = nil
            }

        case .failure(let error):
            logger.error("Failed to queue lip sync generation: \(error.localizedDescription)")
            await MainActor.run {
                alertTitle = "Lip Sync Generation Failed"
                alertMessage = ServerError.detailedMessage(from: error)
                showErrorAlert = true
                generatingLipSyncForAnimation = nil
                activeAnimationLipSyncJob = nil
            }
        }

        await MainActor.run {
            generateLipSyncTask = nil
        }
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
            alertTitle = "Invalid Name"
            alertMessage = "Animation name cannot be empty."
            showErrorAlert = true
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
        case .success(let fetchedAnimation):
            fetchedAnimation.metadata.title = newTitle
            let saveResult = await server.saveAnimation(animation: fetchedAnimation)
            switch saveResult {
            case .success:
                await MainActor.run {
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
                    alertTitle = "Animation Renamed"
                    alertMessage = "Renamed animation to \(newTitle)."
                    showErrorAlert = true
                }
            case .failure(let error):
                let message = ServerError.detailedMessage(from: error)
                logger.warning("Unable to save renamed animation: \(message)")
                await MainActor.run {
                    alertTitle = "Unable to Rename Animation"
                    alertMessage = message
                    showErrorAlert = true
                }
            }

        case .failure(let error):
            let message = ServerError.detailedMessage(from: error)
            logger.warning("Unable to load animation before rename: \(message)")
            await MainActor.run {
                alertTitle = "Unable to Rename Animation"
                alertMessage = message
                showErrorAlert = true
            }
        }

        await MainActor.run {
            isRenamingAnimation = false
            renameAnimationTask = nil
            renameAnimationId = nil
            renameAnimationTitle = ""
            renameOriginalTitle = ""
        }
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

        await MainActor.run {
            isDeletingAnimation = false
            showDeleteConfirmation = false
        }

        switch result {
        case .success:
            await MainActor.run {
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
                alertTitle = "Animation Deleted"
                alertMessage = "Deleted \(animationTitle(for: animationId))."
                showErrorAlert = true
            }
        case .failure(let error):
            let message = ServerError.detailedMessage(from: error)
            logger.warning("Unable to delete animation \(animationId): \(message)")
            await MainActor.run {
                pendingDeleteAnimation = nil
                alertTitle = "Unable to Delete Animation"
                alertMessage = message
                showErrorAlert = true
            }
        }

        await MainActor.run {
            deleteAnimationTask = nil
        }
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

    @MainActor
    private func handleAnimationJobCompletion(
        info: JobStatusStore.JobInfo,
        animationId: AnimationIdentifier
    ) {
        let targetId = info.animationLipSyncDetails?.animationId ?? animationId
        let displayName = animationTitle(for: targetId)

        switch info.status {
        case .completed:
            alertTitle = "Lip Sync Ready"
            if let result = info.animationLipSyncResult {
                let trackDescription =
                    result.updatedTracks == 1
                    ? "1 track"
                    : "\(result.updatedTracks) tracks"
                alertMessage =
                    "Lip sync data for \(displayName) finished processing. \(trackDescription) updated."
            } else {
                alertMessage = "Lip sync data for \(displayName) finished processing."
            }
            showErrorAlert = true
        case .failed:
            let message =
                info.result?.isEmpty == false
                ? info.result!
                : "The server could not generate lip sync for \(displayName)."
            alertTitle = "Lip Sync Failed"
            alertMessage = message
            showErrorAlert = true
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
        jobEventsTask = nil
    }

    func loadAnimationForEditing(animationId: AnimationIdentifier) {
        loadAnimationTask?.cancel()

        loadAnimationTask = Task {
            let result = await server.getAnimation(animationId: animationId)
            switch result {
            case .success(let animation):
                await MainActor.run {
                    animationToEdit = animation
                    navigateToEditor = true
                }
            case .failure(let error):
                let message = "Error: \(error.localizedDescription)"
                logger.warning("Unable to load animation for editing: \(message)")
                await MainActor.run {
                    alertTitle = "Unable to Load Animation"
                    alertMessage = message
                    showErrorAlert = true
                }
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
                logger.info("Animation Scheduled: \(message)")
            case .failure(let error):
                let message = ServerError.detailedMessage(from: error)
                logger.warning("Unable to schedule animation: \(message)")
                await MainActor.run {
                    alertTitle = "Unable to Schedule Animation"
                    alertMessage = message
                    showErrorAlert = true
                }
            }
        }
    }

    @MainActor
    func playAnimationForFilming(animationId: AnimationIdentifier?) {
        guard let animationId = animationId else {
            logger.debug("playAnimationForFilming was called with a nil selection")
            return
        }

        logger.info("Starting filming countdown flow for animation \(animationId)")
        filmingFlowTask?.cancel()

        let countdownSeconds = max(0, filmingCountdownSeconds)
        filmingFlowTask = Task {
            await performFilmingCountdownFlow(
                animationId: animationId, countdownSeconds: countdownSeconds)
        }
    }

    @MainActor
    private func presentAudioPlaybackError(_ error: AudioError) {
        alertTitle = "Unable to Play Alignment Sound"
        alertMessage = audioErrorMessage(for: error)
        showErrorAlert = true
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
        logger.info("Cancelling filming countdown flow")
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
            logger.info("Filming countdown cancelled")
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
                logger.info("Animation Interrupt Scheduled: \(message)")
            case .failure(let error):
                let message = ServerError.detailedMessage(from: error)
                logger.warning("Unable to schedule animation interrupt: \(message)")
                await MainActor.run {
                    alertTitle = "Unable to Interrupt Animation"
                    alertMessage = message
                    showErrorAlert = true
                }
            }
        }
    }
}

struct AnimationTable_Previews: PreviewProvider {
    static var previews: some View {
        AnimationTable(creature: .mock())
    }
}

private enum FilmingPhase: Equatable {
    case countdown(secondsRemaining: Int)
    case playingCue
}

private struct FilmingCountdownOverlay: View {
    let phase: FilmingPhase
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                switch phase {
                case .countdown(let secondsRemaining):
                    Text("\(secondsRemaining)")
                        .font(.system(size: 160, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                    Text(
                        secondsRemaining == 0
                            ? "Alignment starting" : "Starting in \(secondsRemaining)"
                    )
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                case .playingCue:
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                    Text("Playing Alignment Sound")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            }
            .padding(40)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            .shadow(radius: 24)
        }
    }
}

private struct RenameAnimationSheet: View {
    @Binding var title: String
    let originalTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Animation")
                .font(.title2.bold())

            Text("Update the animation name. This change is saved to the server immediately.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Animation Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard canSave else { return }
                    onSave()
                }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && trimmedTitle != originalTitle
    }
}
