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
                        )
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
                generateLipSyncTask = nil
                jobEventsTask = nil
                activeAnimationLipSyncJob = nil
                generatingLipSyncForAnimation = nil
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
                if let job = activeAnimationLipSyncJob {
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

        playAnimationTask?.cancel()

        let manager = creatureManager
        let universe = activeUniverse

        playAnimationTask = Task {
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
