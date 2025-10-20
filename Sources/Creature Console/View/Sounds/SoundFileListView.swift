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
    @State private var lipSyncTask: Task<Void, Never>? = nil
    @State private var pendingRegenerateSound: SoundIdentifier? = nil
    @State private var showRegenerateConfirmation = false

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
                if let name = generatingLipSyncFor {
                    overlayProgress(message: "Generating lip sync for \(name)…")
                } else if let name = preparingFile {
                    overlayProgress(message: "Preparing \(name)…")
                }
            }
            .animation(.default, value: generatingLipSyncFor != nil || preparingFile != nil)
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
    private func overlayProgress(message: String) -> some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                Text(message)
                    .font(.callout)
            }
            .padding(16)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
        .transition(.opacity)
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
                lipSyncTask = nil
            }
            return
        }

        switch result {
        case .success:
            let refreshSucceeded = await importFromServerIfNeeded(force: true)

            await MainActor.run {
                if refreshSucceeded {
                    alertTitle = "Lip Sync Ready"
                    alertMessage = "Lip sync data for \(soundId) is available."
                    showAlert = true
                }
            }
        case .failure(let error):
            await MainActor.run {
                alertTitle = "Error"
                alertMessage = ServerError.detailedMessage(from: error)
                showAlert = true
            }
        }

        await MainActor.run {
            generatingLipSyncFor = nil
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
