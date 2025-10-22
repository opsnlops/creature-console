import Common
import OSLog
import SwiftData
import SwiftUI

struct SoundFileListView: View {
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundFileListView")

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \SoundModel.id, order: .forward)
    private var sounds: [SoundModel]

    // Our Server
    let server = CreatureServerClient.shared
    let audioManager = AudioManager.shared

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    @State private var selection: SoundIdentifier? = nil
    @State private var playSoundTask: Task<Void, Never>? = nil
    @State private var preparingFile: String? = nil
    @State private var generatingLipSyncFor: SoundIdentifier? = nil
    @State private var activeLipSyncJob: (soundId: SoundIdentifier, jobId: String)?
    @State private var lipSyncTask: Task<Void, Never>? = nil
    @State private var pendingRegenerateSound: SoundIdentifier? = nil
    @State private var showRegenerateConfirmation = false
    @State private var observedJobInfo: JobStatusStore.JobInfo?
    @State private var jobEventsTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack {
                if !sounds.isEmpty {
                    Table(sounds, selection: $selection) {
                        TableColumn("File Name") { s in
                            Text(s.id)
                        }
                        .width(min: 300, ideal: 500)

                        TableColumn("Size (bytes)") { s in
                            Text(s.size, format: .number)
                        }
                        .width(min: 120)

                        TableColumn("Text?") { s in
                            Text(s.transcript.isEmpty ? "" : "✅")
                        }
                        .width(100)

                        TableColumn("Lip Sync?") { s in
                            Text(s.lipsync.isEmpty ? "" : "✅")
                        }
                        .width(110)

                    }
                    .contextMenu(forSelectionType: SoundIdentifier.self) {
                        (items: Set<SoundIdentifier>) in
                        if let soundId = items.first ?? selection,
                            let sound = sounds.first(where: { $0.id == soundId })
                        {
                            let isWavFile = sound.id.lowercased().hasSuffix(".wav")
                            Button {
                                playOnServer(fileName: sound.id)
                            } label: {
                                Label(
                                    "Play Sound File On Server",
                                    systemImage: "music.note.tv")
                            }

                            Button {
                                playLocally(fileName: sound.id)
                            } label: {
                                Label(
                                    "Play Sound File Locally",
                                    systemImage: "music.quarternote.3")
                            }

                            Button {
                                // TODO: show transcript UI
                            } label: {
                                Label("View Transcript", systemImage: "text.bubble.fill")
                            }
                            .disabled(sound.transcript.isEmpty)

                            if isWavFile {
                                if sound.lipsync.isEmpty {
                                    Button {
                                        startLipSyncGeneration(for: sound.id, allowOverwrite: false)
                                    } label: {
                                        Label("Generate Lip Sync File", systemImage: "waveform")
                                    }
                                    .disabled(generatingLipSyncFor != nil)
                                } else {
                                    Button {
                                        pendingRegenerateSound = sound.id
                                        showRegenerateConfirmation = true
                                    } label: {
                                        Label(
                                            "Regenerate Lip Sync File…",
                                            systemImage: "arrow.triangle.2.circlepath"
                                        )
                                    }
                                    .disabled(generatingLipSyncFor != nil)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Sounds", systemImage: "speaker.wave.2")
                    } description: {
                        Text("Sounds will appear once imported from the server.")
                    } actions: {
                        Button("Import from Server") {
                            Task { await importFromServerIfNeeded(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .navigationTitle("Sound Files")
            #if os(macOS)
                .navigationSubtitle("Number of Sounds: \(sounds.count)")
            #endif
            .overlay {
                if let job = activeLipSyncJob {
                    overlayProgress(
                        message: overlayMessage(for: observedJobInfo, soundId: job.soundId),
                        progress: observedJobInfo?.progressPercentage
                    )
                } else if let name = generatingLipSyncFor {
                    overlayProgress(
                        message: "Submitting lip sync job for \(name)…",
                        progress: nil
                    )
                } else if let name = preparingFile {
                    overlayProgress(message: "Preparing \(name)…", progress: nil)
                }
            }
            .animation(.default, value: generatingLipSyncFor != nil || preparingFile != nil)
            .task(id: activeLipSyncJob?.jobId) {
                jobEventsTask?.cancel()
                observedJobInfo = nil

                guard let job = activeLipSyncJob else { return }
                jobEventsTask = Task {
                    let stream = await JobStatusStore.shared.events()
                    for await event in stream {
                        switch event {
                        case .updated(let info) where info.jobId == job.jobId:
                            await MainActor.run {
                                observedJobInfo = info
                                if info.isTerminal {
                                    handleJobCompletion(info: info, soundId: job.soundId)
                                }
                            }
                            if info.isTerminal {
                                await JobStatusStore.shared.remove(jobId: job.jobId)
                                return
                            }
                        case .removed(let removedId) where removedId == job.jobId:
                            await MainActor.run {
                                finalizeActiveJob()
                            }
                            return
                        default:
                            continue
                        }
                    }
                }
            }
            .onDisappear {
                jobEventsTask?.cancel()
                jobEventsTask = nil
            }
            .confirmationDialog(
                "Regenerate Lip Sync?",
                isPresented: $showRegenerateConfirmation,
                presenting: pendingRegenerateSound
            ) { soundId in
                Button("Regenerate", role: .destructive) {
                    startLipSyncGeneration(for: soundId, allowOverwrite: true)
                }
                Button("Cancel", role: .cancel) {
                    pendingRegenerateSound = nil
                }
            } message: { soundId in
                Text(
                    "Generating lip sync again will overwrite the existing data for \(soundId). This can take up to 30 seconds."
                )
            }
        }
    }

    private func importFromServerIfNeeded(force: Bool) async -> Bool {
        // If we already have sounds and not forcing, skip fetch
        if !force && !sounds.isEmpty { return false }

        var didImport = false
        do {
            let importer = SoundImporter(modelContainer: modelContext.container)
            logger.info("Fetching sound list from server for SwiftData import")
            let result = await server.listSounds()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                logger.info("Imported \(list.count) sounds into SwiftData")
                didImport = true
            case .failure(let error):
                await MainActor.run {
                    alertTitle = "Error"
                    alertMessage = ServerError.detailedMessage(from: error)
                    showAlert = true
                }
            }
        } catch {
            await MainActor.run {
                alertTitle = "Error"
                alertMessage = "Error importing sounds: \(error.localizedDescription)"
                showAlert = true
            }
        }
        return didImport
    }

    @ViewBuilder
    private func overlayProgress(message: String, progress: Double?) -> some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 10) {
                if let progress {
                    ProgressView(value: progress, total: 100)
                } else {
                    ProgressView()
                }
                Text(message)
                    .font(.callout)
                if let progress {
                    Text(String(format: "%.0f%%", progress))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
        .transition(.opacity)
    }

    private func overlayMessage(
        for info: JobStatusStore.JobInfo?,
        soundId: SoundIdentifier
    ) -> String {
        guard let info else {
            return "Submitting lip sync job for \(soundId)…"
        }

        let displayName = info.lipSyncDetails?.soundFile ?? soundId
        let isRegeneration = info.lipSyncDetails?.allowOverwrite == true

        switch info.status {
        case .queued:
            return isRegeneration
                ? "Lip sync regeneration queued for \(displayName)…"
                : "Lip sync job queued for \(displayName)…"
        case .running:
            return isRegeneration
                ? "Regenerating lip sync for \(displayName)…"
                : "Generating lip sync for \(displayName)…"
        case .completed:
            return "Lip sync completed for \(displayName)"
        case .failed:
            return "Lip sync failed for \(displayName)"
        case .unknown:
            return "Processing lip sync job for \(displayName)…"
        }
    }

    @MainActor
    private func handleJobCompletion(info: JobStatusStore.JobInfo, soundId: SoundIdentifier) {
        switch info.status {
        case .completed:
            let name = info.lipSyncDetails?.soundFile ?? soundId
            alertTitle = "Lip Sync Ready"
            alertMessage = "Lip sync data for \(name) is available."
            showAlert = true
        case .failed:
            let message =
                info.result?.isEmpty == false
                ? info.result!
                : "The server was unable to generate lip sync for \(soundId)."
            alertTitle = "Lip Sync Failed"
            alertMessage = message
            showAlert = true
        default:
            break
        }

        finalizeActiveJob()
    }

    @MainActor
    private func finalizeActiveJob() {
        generatingLipSyncFor = nil
        activeLipSyncJob = nil
        observedJobInfo = nil
        jobEventsTask = nil
    }

    private func startLipSyncGeneration(
        for soundId: SoundIdentifier,
        allowOverwrite: Bool
    ) {
        guard generatingLipSyncFor == nil else { return }

        pendingRegenerateSound = nil
        generatingLipSyncFor = soundId
        lipSyncTask?.cancel()
        lipSyncTask = Task {
            await performLipSyncGeneration(for: soundId, allowOverwrite: allowOverwrite)
        }
    }

    private func performLipSyncGeneration(
        for soundId: SoundIdentifier,
        allowOverwrite: Bool
    ) async {
        let result = await server.generateLipSync(for: soundId, allowOverwrite: allowOverwrite)

        if Task.isCancelled {
            await MainActor.run {
                generatingLipSyncFor = nil
                activeLipSyncJob = nil
                lipSyncTask = nil
            }
            return
        }

        switch result {
        case .success(let job):
            logger.info("Lip sync job queued: \(job.jobId) for \(soundId)")
            if let data = try? JSONEncoder().encode(
                LipSyncJobDetails(soundFile: soundId, allowOverwrite: allowOverwrite)
            ), let detailsString = String(data: data, encoding: .utf8) {
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
                activeLipSyncJob = (soundId, job.jobId)
                generatingLipSyncFor = soundId
                observedJobInfo = nil
            }
        case .failure(let error):
            await MainActor.run {
                alertTitle = "Error"
                alertMessage = ServerError.detailedMessage(from: error)
                showAlert = true
                generatingLipSyncFor = nil
                activeLipSyncJob = nil
            }
        }

        await MainActor.run {
            lipSyncTask = nil
        }
    }

    private func playOnServer(fileName: String) {
        playSoundTask?.cancel()
        playSoundTask = Task {
            let result = await server.playSound(fileName)
            switch result {
            case .success:
                break
            case .failure(let error):
                await MainActor.run {
                    alertTitle = "Error"
                    alertMessage = ServerError.detailedMessage(from: error)
                    showAlert = true
                }
            }
        }
    }

    private func playLocally(fileName: String) {
        playSoundTask?.cancel()
        playSoundTask = Task {
            await MainActor.run { preparingFile = fileName }
            let urlRequest = server.getSoundURL(fileName)
            switch urlRequest {
            case .success(let url):
                if fileName.lowercased().hasSuffix(".wav") {
                    let prepResult = await audioManager.prepareMonoPreview(
                        for: url, cacheKey: fileName)
                    switch prepResult {
                    case .success(let monoURL):
                        let armResult = audioManager.armPreviewPlayback(fileURL: monoURL)
                        switch armResult {
                        case .success:
                            _ = audioManager.startArmedPreview(in: 0.1)
                            await MainActor.run { preparingFile = nil }
                        case .failure(let err):
                            await MainActor.run {
                                alertTitle = "Error"
                                alertMessage = "Error: \(err)"
                                showAlert = true
                                preparingFile = nil
                            }
                        }
                    case .failure(let err):
                        await MainActor.run {
                            alertTitle = "Error"
                            alertMessage = "Error: \(err)"
                            showAlert = true
                            preparingFile = nil
                        }
                    }
                } else {
                    _ = audioManager.playURL(url)
                    await MainActor.run { preparingFile = nil }
                }
            case .failure(let error):
                await MainActor.run {
                    alertTitle = "Error"
                    alertMessage = ServerError.detailedMessage(from: error)
                    showAlert = true
                    preparingFile = nil
                }
            }
        }
    }
}

#Preview {
    SoundFileListView()
}
