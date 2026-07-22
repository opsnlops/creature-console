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

    @State private var errorAlert: ErrorAlert?

    @State private var selection: SoundIdentifier? = nil
    @State private var playSoundTask: Task<Void, Never>? = nil
    @State private var preparingFile: String? = nil
    @State private var generatingLipSyncFor: SoundIdentifier? = nil
    @State private var activeLipSyncJob: (soundId: SoundIdentifier, jobId: String)?
    @State private var lipSyncTask: Task<Void, Never>? = nil
    @State private var pendingRegenerateSound: SoundIdentifier? = nil
    @State private var showRegenerateConfirmation = false
    @State private var observedJobInfo: JobStatusStore.JobInfo?
    @State private var soundToShare: String? = nil
    @State private var identifiedProvenance: IdentifiedProvenance? = nil
    @State private var loadingProvenanceFor: String? = nil
    @State private var provenanceTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            VStack {
                if !sounds.isEmpty {
                    Table(sounds, selection: $selection) {
                        TableColumn("File Name") { s in
                            if s.title.isEmpty {
                                Text(s.id)
                            } else {
                                // A dialog render: lead with its embedded title, keep the
                                // (UUID) file name as a quiet subtitle.
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title)
                                    Text(s.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .width(min: 300, ideal: 500)

                        TableColumn("Size (bytes)") { s in
                            Text(s.size, format: .number)
                        }
                        .width(min: 120)

                        TableColumn("Text?") { s in
                            // ✅ for a sidecar transcript OR embedded (iXML) script text.
                            Text(s.transcript.isEmpty && !s.hasEmbeddedScript ? "" : "✅")
                        }
                        .width(100)

                        TableColumn("Lip Sync?") { s in
                            // ✅ for a sidecar Rhubarb file OR embedded (iXML) mouth cues.
                            Text(s.lipsync.isEmpty && !s.hasEmbeddedLipsync ? "" : "✅")
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
                                Button {
                                    showProvenance(for: sound.id)
                                } label: {
                                    Label(
                                        "View Script Provenance…",
                                        systemImage: "doc.text.magnifyingglass")
                                }
                                .disabled(loadingProvenanceFor != nil)

                                ShareableSoundButton(fileName: sound.id, trigger: $soundToShare)

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
                    } primaryAction: { items in
                        // Row activation (double-click on macOS, tap on iOS): preview the
                        // sound locally, like Finder.
                        if let soundId = items.first ?? selection {
                            playLocally(fileName: soundId)
                        }
                    }
                    .shareableSoundFlow(fileName: $soundToShare)
                    .sheet(item: $identifiedProvenance) { identified in
                        DialogProvenanceView(
                            fileName: identified.fileName, provenance: identified.provenance)
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
            .errorAlert($errorAlert)
            .navigationTitle("Sound Files")
            .bottomToolbarInset()
            #if os(macOS)
                .navigationSubtitle("Number of Sounds: \(sounds.count)")
            #endif
            .overlay {
                if let job = activeLipSyncJob {
                    ProcessingOverlayView(
                        message: overlayMessage(for: observedJobInfo, soundId: job.soundId),
                        progress: observedJobInfo?.progressPercentage
                    )
                } else if let name = generatingLipSyncFor {
                    ProcessingOverlayView(
                        message: "Submitting lip sync job for \(name)…",
                        progress: nil
                    )
                } else if let name = preparingFile {
                    ProcessingOverlayView(message: "Preparing \(name)…", progress: nil)
                } else if let name = loadingProvenanceFor {
                    ProcessingOverlayView(message: "Reading provenance for \(name)…", progress: nil)
                }
            }
            .animation(.default, value: generatingLipSyncFor != nil || preparingFile != nil)
            .watchJob(activeLipSyncJob?.jobId) { info in
                observedJobInfo = info
            } onTerminal: { info in
                observedJobInfo = info
                handleJobCompletion(info: info, soundId: activeLipSyncJob?.soundId ?? "")
            } onRemoved: {
                finalizeActiveJob()
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
            logger.debug("Fetching sound list from server for SwiftData import")
            let result = await server.listSounds()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                logger.debug("Imported \(list.count) sounds into SwiftData")
                didImport = true
            case .failure(let error):
                errorAlert = ErrorAlert(error: error)
            }
        } catch {
            errorAlert = ErrorAlert(
                message: "Error importing sounds: \(error.localizedDescription)")
        }
        return didImport
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
            errorAlert = ErrorAlert(
                title: "Lip Sync Ready", message: "Lip sync data for \(name) is available.")
        case .failed:
            let message =
                info.result?.isEmpty == false
                ? info.result!
                : "The server was unable to generate lip sync for \(soundId)."
            errorAlert = ErrorAlert(title: "Lip Sync Failed", message: message)
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
            generatingLipSyncFor = nil
            activeLipSyncJob = nil
            lipSyncTask = nil
            return
        }

        switch result {
        case .success(let job):
            logger.debug("Lip sync job queued: \(job.jobId) for \(soundId)")
            await JobStatusStore.shared.seedQueued(
                job, details: LipSyncJobDetails(soundFile: soundId, allowOverwrite: allowOverwrite))

            activeLipSyncJob = (soundId, job.jobId)
            generatingLipSyncFor = soundId
            observedJobInfo = nil
        case .failure(let error):
            errorAlert = ErrorAlert(error: error)
            generatingLipSyncFor = nil
            activeLipSyncJob = nil
        }

        lipSyncTask = nil
    }

    private func showProvenance(for fileName: String) {
        guard loadingProvenanceFor == nil else { return }
        loadingProvenanceFor = fileName
        provenanceTask?.cancel()
        provenanceTask = Task {
            let result = await server.fetchDialogProvenance(fileName: fileName)
            loadingProvenanceFor = nil
            provenanceTask = nil
            switch result {
            case .success(let provenance):
                identifiedProvenance = IdentifiedProvenance(
                    fileName: fileName, provenance: provenance)
            case .failure(let error):
                errorAlert = ErrorAlert(title: "No Script Provenance", error: error)
            }
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
                errorAlert = ErrorAlert(error: error)
            }
        }
    }

    private func playLocally(fileName: String) {
        playSoundTask?.cancel()
        playSoundTask = Task {
            preparingFile = fileName
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
                            preparingFile = nil
                        case .failure(let err):
                            errorAlert = ErrorAlert(message: "Error: \(err)")
                            preparingFile = nil
                        }
                    case .failure(let err):
                        errorAlert = ErrorAlert(message: "Error: \(err)")
                        preparingFile = nil
                    }
                } else {
                    _ = audioManager.playURL(url)
                    preparingFile = nil
                }
            case .failure(let error):
                errorAlert = ErrorAlert(error: error)
                preparingFile = nil
            }
        }
    }
}

#Preview {
    SoundFileListView()
}
