import SwiftUI
import SwiftData
import Common
import OSLog

struct SoundFileListView: View {
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundFileListView")

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \SoundModel.id, order: .forward)
    private var sounds: [SoundModel]

    // Our Server
    let server = CreatureServerClient.shared
    let audioManager = AudioManager.shared

    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    @State private var selection: SoundModel.ID? = nil
    @State private var playSoundTask: Task<Void, Never>? = nil
    @State private var preparingFile: String? = nil

    var body: some View {
        NavigationStack {
            VStack {
                if !sounds.isEmpty {
                    Table(of: SoundModel.self, selection: $selection) {
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

                    } rows: {
                        ForEach(sounds) { sound in
                            TableRow(sound)
                                .contextMenu {
                                    Button {
                                        playOnServer(fileName: sound.id)
                                    } label: {
                                        Label("Play Sound File On Server", systemImage: "music.note.tv")
                                    }

                                    Button {
                                        playLocally(fileName: sound.id)
                                    } label: {
                                        Label("Play Sound File Locally", systemImage: "music.quarternote.3")
                                    }

                                    Button {
                                        // TODO: show transcript UI
                                    } label: {
                                        Label("View Transcript", systemImage: "text.bubble.fill")
                                    }
                                    .disabled(sound.transcript.isEmpty)
                                }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Sounds", systemImage: "speaker.wave.2")
                    } description: {
                        Text("Sounds will appear once imported from the server.")
                    } actions: {
                        Button("Import from Server") { Task { await importFromServerIfNeeded(force: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .navigationTitle("Sound Files")
            #if os(macOS)
            .navigationSubtitle("Number of Sounds: \(sounds.count)")
            #endif
            .task {
                await importFromServerIfNeeded(force: false)
            }
            .overlay {
                if let name = preparingFile {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing \(name)…")
                                .font(.callout)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.default, value: preparingFile != nil)
        }
    }

    private func importFromServerIfNeeded(force: Bool) async {
        // If we already have sounds and not forcing, skip fetch
        if !force && !sounds.isEmpty { return }
        do {
            let importer = SoundImporter(modelContainer: modelContext.container)
            logger.info("Fetching sound list from server for SwiftData import")
            let result = await server.listSounds()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                logger.info("Imported \(list.count) sounds into SwiftData")
            case .failure(let error):
                await MainActor.run {
                    alertMessage = "Error: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error importing sounds: \(error.localizedDescription)"
                showErrorAlert = true
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
                await MainActor.run {
                    alertMessage = "Error: \(error.localizedDescription)"
                    showErrorAlert = true
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
                    let prepResult = await audioManager.prepareMonoPreview(for: url, cacheKey: fileName)
                    switch prepResult {
                    case .success(let monoURL):
                        let armResult = audioManager.armPreviewPlayback(fileURL: monoURL)
                        switch armResult {
                        case .success:
                            _ = audioManager.startArmedPreview(in: 0.1)
                            await MainActor.run { preparingFile = nil }
                        case .failure(let err):
                            await MainActor.run {
                                alertMessage = "Error: \(err)"
                                showErrorAlert = true
                                preparingFile = nil
                            }
                        }
                    case .failure(let err):
                        await MainActor.run {
                            alertMessage = "Error: \(err)"
                            showErrorAlert = true
                            preparingFile = nil
                        }
                    }
                } else {
                    _ = audioManager.playURL(url)
                    await MainActor.run { preparingFile = nil }
                }
            case .failure(let error):
                await MainActor.run {
                    alertMessage = "Error: \(error.localizedDescription)"
                    showErrorAlert = true
                    preparingFile = nil
                }
            }
        }
    }
}

#Preview {
    SoundFileListView()
}
