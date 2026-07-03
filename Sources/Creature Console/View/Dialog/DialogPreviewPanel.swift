import AVFoundation
import Common
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// "Listen before you render" panel. Generates (or loads from cache) a preview take for the
/// current turns, plays the mono mixdown locally, lets the author flip between cached takes,
/// and exports the mono / 17-channel WAVs for inspection in Audacity.
///
/// Preview is always keyed by the in-memory `turns` (the server's cache key is `sha256(turns)`),
/// so the chosen `selectedGenerationId` lines up whether the eventual render goes by `script_id`
/// or inline turns.
struct DialogPreviewPanel: View {

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DialogPreviewPanel")

    let turns: [DialogScriptTurn]
    /// The take chosen here is shared with the render panel so a render uses exactly what was
    /// auditioned. `nil` means "latest / server decides".
    @Binding var selectedGenerationId: DialogGenerationIdentifier?

    private let server = CreatureServerClient.shared
    private let audioManager = AudioManager.shared

    @State private var isWorking = false
    @State private var statusMessage: String? = nil
    @State private var meta: DialogPreviewMetaDTO? = nil
    @State private var takes: [DialogPreviewLookupDTO.Generation] = []

    @State private var showError = false
    @State private var errorMessage = ""

    // Export state (cross-platform via .fileExporter)
    @State private var exportData: Data? = nil
    @State private var exportFilename = "dialog.wav"
    @State private var exportContentType: UTType = .wav
    @State private var showExporter = false

    private var turnsAreReady: Bool {
        !turns.isEmpty
            && turns.allSatisfy {
                !$0.creatureId.trimmingCharacters(in: .whitespaces).isEmpty
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Listen & Export").font(.headline)
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }

            if !turnsAreReady {
                Text(
                    "Add at least one turn, with a creature and some text in each, to preview the audio."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    preview(regenerate: false)
                } label: {
                    Label("Preview", systemImage: "play.circle")
                }
                .disabled(!turnsAreReady || isWorking)

                Button {
                    preview(regenerate: true)
                } label: {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!turnsAreReady || isWorking)

                Button {
                    refreshTakes()
                } label: {
                    Label("Find Takes", systemImage: "square.stack.3d.up")
                }
                .disabled(!turnsAreReady || isWorking)
            }

            if let meta {
                HStack(spacing: 8) {
                    Image(systemName: meta.cached ? "bolt.fill" : "sparkles")
                        .foregroundStyle(meta.cached ? .yellow : .blue)
                    Text(
                        "\(meta.cached ? "Cached take" : "Fresh take") • \(formatDuration(meta.durationSeconds))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }

            if !takes.isEmpty {
                takePicker
            }

            if meta != nil {
                HStack(spacing: 12) {
                    Button {
                        exportMono()
                    } label: {
                        Label("Export Mono WAV", systemImage: "waveform")
                    }
                    .disabled(isWorking)

                    Button {
                        exportMultichannel()
                    } label: {
                        Label("Export 17-Channel WAV", systemImage: "square.split.1x2")
                    }
                    .disabled(isWorking)

                    Button {
                        exportShareable()
                    } label: {
                        Label("Export Shareable Ogg", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .onChange(of: turns) {
            // Takes are keyed by sha256(turns) server-side; a turn change means everything
            // shown here belongs to a different cache key now.
            meta = nil
            takes = []
            statusMessage = nil
        }
        .alert("Preview Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: AudioFileDocument(data: exportData ?? Data()),
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                logger.info("exported WAV to \(url.path)")
                statusMessage = "Exported \(url.lastPathComponent)"
            case .failure(let error):
                presentError("Export failed: \(error.localizedDescription)")
            }
            exportData = nil
        }
    }

    private var takePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cached takes (newest first)").font(.caption).foregroundStyle(.secondary)
            Picker("Take", selection: $selectedGenerationId) {
                ForEach(Array(takes.enumerated()), id: \.element.id) { index, take in
                    Text(takeLabel(take, index: index))
                        .tag(Optional(take.generationId))
                }
            }
            .labelsHidden()
            .onChange(of: selectedGenerationId) { _, newValue in
                // Re-audition the newly chosen take. Skip when the selection was cleared
                // (turns changed) or when it's the take we're already showing (preview()
                // writes the id back after each request).
                guard let newValue, newValue != meta?.generationId, turnsAreReady else {
                    return
                }
                preview(regenerate: false)
            }
        }
    }

    // MARK: - Actions

    /// Resolve preview meta, transparently riding the generation job when the server
    /// queues one (fresh takes / long scenes). Cache hits return immediately; queued
    /// generations publish progress into `statusMessage` and resolve from the job's
    /// completion result.
    private func resolveMeta(_ request: DialogPreviewRequest) async -> Result<
        DialogPreviewMetaDTO, ServerError
    > {
        switch await server.dialogPreviewMeta(request) {
        case .failure(let error):
            return .failure(error)
        case .success(.meta(let dto)):
            return .success(dto)
        case .success(.queued(let job)):
            await JobStatusStore.shared.seedQueued(job)
            for await event in await JobStatusStore.shared.events(forJob: job.jobId) {
                switch event {
                case .updated(let info):
                    let percent = Int((info.progress ?? 0) * 100)
                    await MainActor.run { statusMessage = "Generating voices… \(percent)%" }
                case .terminal(let info):
                    guard info.status == .completed else {
                        return .failure(
                            .serverError(
                                info.result ?? "The preview generation failed on the server."))
                    }
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    guard let result = info.result, let data = result.data(using: .utf8),
                        let dto = try? decoder.decode(DialogPreviewMetaDTO.self, from: data)
                    else {
                        return .failure(
                            .dataFormatError(
                                "The preview job finished but its result could not be decoded."))
                    }
                    return .success(dto)
                case .removed:
                    return .failure(
                        .serverError("The preview job was removed before it finished."))
                }
            }
            return .failure(.serverError("The preview job stream ended unexpectedly."))
        }
    }

    private func preview(regenerate: Bool) {
        guard turnsAreReady else { return }
        isWorking = true
        statusMessage = regenerate ? "Generating a fresh take…" : "Preparing preview…"
        let request = DialogPreviewRequest.fromTurns(
            turns,
            generationId: regenerate ? nil : selectedGenerationId,
            regenerate: regenerate ? true : nil)
        Task {
            let result = await resolveMeta(request)
            switch result {
            case .success(let dto):
                await MainActor.run {
                    meta = dto
                    selectedGenerationId = dto.generationId
                }
                await playMeta(dto)
            case .failure(let error):
                await MainActor.run {
                    isWorking = false
                    statusMessage = nil
                    presentError(ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func playMeta(_ dto: DialogPreviewMetaDTO) async {
        guard let url = server.makeAbsoluteURL(fromRelativePath: dto.audioUrl) else {
            await MainActor.run {
                isWorking = false
                presentError("Could not build the preview audio URL.")
            }
            return
        }
        // Download with the configured request headers (proxy/API key/trace) to a local file,
        // then play locally — more robust than streaming the URL straight into AVPlayer.
        let prep = await audioManager.prepareMonoPreview(
            for: url, cacheKey: "\(dto.cacheKey)-\(dto.generationId.uuidString.lowercased()).wav")
        await MainActor.run {
            isWorking = false
            switch prep {
            case .success(let localURL):
                statusMessage = "Playing preview…"
                if case .failure(let audioError) = audioManager.playURL(localURL) {
                    presentError("Playback failed: \(audioError.localizedDescription)")
                }
            case .failure(let audioError):
                presentError("Could not load preview audio: \(audioError.localizedDescription)")
            }
        }
    }

    private func refreshTakes() {
        guard turnsAreReady else { return }
        isWorking = true
        statusMessage = "Looking up cached takes…"
        Task {
            let result = await server.dialogPreviewLookup(.fromTurns(turns))
            await MainActor.run {
                isWorking = false
                switch result {
                case .success(let dto):
                    takes = dto.generations
                    if selectedGenerationId == nil {
                        selectedGenerationId = dto.latestGenerationId
                    }
                    statusMessage = "\(dto.generations.count) cached take(s)"
                case .failure(.notFound):
                    takes = []
                    statusMessage = "No cached takes yet — Preview to generate one."
                case .failure(let error):
                    presentError(ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func exportMono() {
        // Ensure we have meta (and therefore an audio URL) for the current selection.
        isWorking = true
        statusMessage = "Fetching mono WAV…"
        let request = DialogPreviewRequest.fromTurns(turns, generationId: selectedGenerationId)
        Task {
            let metaResult = await resolveMeta(request)
            guard case .success(let dto) = metaResult,
                let url = server.makeAbsoluteURL(fromRelativePath: dto.audioUrl)
            else {
                await MainActor.run {
                    isWorking = false
                    presentError("Could not resolve the mono audio for export.")
                }
                return
            }
            let dataResult = await server.downloadRawData(from: url)
            await MainActor.run {
                isWorking = false
                switch dataResult {
                case .success(let data):
                    exportData = data
                    exportFilename = "dialog-mono-\(dto.generationId.uuidString.lowercased()).wav"
                    exportContentType = .wav
                    showExporter = true
                case .failure(let error):
                    presentError(ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func exportShareable() {
        // Resolve meta for the current selection so we have the cache key + take id,
        // then let the server encode that take's cached PCM to Ogg/Opus.
        isWorking = true
        statusMessage = "Encoding shareable Ogg…"
        let request = DialogPreviewRequest.fromTurns(turns, generationId: selectedGenerationId)
        Task {
            let metaResult = await resolveMeta(request)
            guard case .success(let dto) = metaResult,
                case .success(let url) = server.dialogPreviewShareableURL(
                    cacheKey: dto.cacheKey, generationId: dto.generationId)
            else {
                await MainActor.run {
                    isWorking = false
                    presentError("Could not resolve the shareable audio for export.")
                }
                return
            }
            let dataResult = await server.downloadRawData(from: url)
            await MainActor.run {
                isWorking = false
                switch dataResult {
                case .success(let data):
                    exportData = data
                    exportFilename =
                        "dialog-preview-\(dto.generationId.uuidString.lowercased().prefix(8)).ogg"
                    exportContentType = .oggAudio
                    showExporter = true
                    statusMessage = "Ready to save shareable Ogg"
                case .failure(let error):
                    presentError(ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func exportMultichannel() {
        isWorking = true
        statusMessage = "Rendering 17-channel WAV…"
        let request = DialogPreviewRequest.fromTurns(turns, generationId: selectedGenerationId)
        Task {
            // Always a job now (server 3.23.0) — long scenes make enormous WAVs. Watch
            // it, then download the assembled file from the ad-hoc sound bucket.
            switch await server.dialogPreviewMultichannel(request) {
            case .failure(let error):
                await MainActor.run {
                    isWorking = false
                    presentError(ServerError.detailedMessage(from: error))
                }
            case .success(let job):
                await JobStatusStore.shared.seedQueued(job)
                for await event in await JobStatusStore.shared.events(forJob: job.jobId) {
                    switch event {
                    case .updated(let info):
                        let percent = Int((info.progress ?? 0) * 100)
                        await MainActor.run {
                            statusMessage = "Rendering 17-channel WAV… \(percent)%"
                        }
                    case .terminal(let info):
                        await finishMultichannelExport(info)
                    case .removed:
                        await MainActor.run {
                            isWorking = false
                            presentError("The export job was removed before it finished.")
                        }
                    }
                }
            }
        }
    }

    private func finishMultichannelExport(_ info: JobStatusStore.JobInfo) async {
        guard info.status == .completed,
            let result = info.result, let data = result.data(using: .utf8),
            let export = try? JSONDecoder().decode(DialogPreviewExportResult.self, from: data)
        else {
            await MainActor.run {
                isWorking = false
                presentError(
                    info.status == .completed
                        ? "The export finished but its result could not be decoded."
                        : (info.result ?? "The 17-channel export failed on the server."))
            }
            return
        }
        guard case .success(let url) = server.getAdHocSoundURL(export.fileName) else {
            await MainActor.run {
                isWorking = false
                presentError("Could not build the download URL for the exported WAV.")
            }
            return
        }
        let dataResult = await server.downloadRawData(from: url)
        await MainActor.run {
            isWorking = false
            switch dataResult {
            case .success(let wavData):
                exportData = wavData
                exportFilename = export.fileName
                exportContentType = .wav
                showExporter = true
                statusMessage = "Ready to save 17-channel WAV"
            case .failure(let error):
                presentError(ServerError.detailedMessage(from: error))
            }
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
        statusMessage = nil
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func takeLabel(_ take: DialogPreviewLookupDTO.Generation, index: Int) -> String {
        let shortId = String(take.generationId.uuidString.lowercased().prefix(8))
        if let date = take.createdAtDate {
            return "#\(index + 1) • \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "#\(index + 1) • \(shortId)"
    }
}
