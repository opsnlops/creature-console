#if os(tvOS)
    import Common
    import OSLog
    import SwiftData
    import SwiftUI

    struct TVSoundboardView: View {

        @Environment(\.modelContext) private var modelContext
        @Query(sort: \SoundModel.id, order: .forward)
        private var sounds: [SoundModel]

        private let server = CreatureServerClient.shared
        private let audioManager = AudioManager.shared
        private let logger = Logger(
            subsystem: "io.opsnlops.CreatureConsole", category: "TVSoundboardView")

        @State private var isRefreshing = false
        @State private var pendingSoundId: SoundIdentifier?
        @State private var alertDescriptor: TVAlertDescriptor?
        @State private var toast: TVStatusToast?
        @State private var toastTask: Task<Void, Never>?

        private var gridColumns: [GridItem] {
            [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 36, alignment: .top)]
        }

        var body: some View {
            ScrollView {
                if sounds.isEmpty && !isRefreshing {
                    emptyState
                        .padding(.horizontal, 80)
                        .padding(.top, 120)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 36) {
                        ForEach(sounds) { sound in
                            soundButton(for: sound)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 60)
                }
            }
            .background(Color.clear.ignoresSafeArea())
            .navigationTitle("Soundboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh(force: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    TVStatusToastView(toast: toast)
                        .padding(.top, 48)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay {
                if isRefreshing {
                    ProgressView("Updating sounds…")
                        .font(.title2)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: isRefreshing)
            .animation(.easeInOut(duration: 0.35), value: toast)
            .alert(item: $alertDescriptor) { descriptor in
                Alert(
                    title: Text(descriptor.title),
                    message: Text(descriptor.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .task {
                await refresh()
            }
            .onDisappear {
                toastTask?.cancel()
            }
        }

        private func soundButton(for sound: SoundModel) -> some View {
            Button {
                triggerSound(sound)
            } label: {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(.blue.opacity(0.7))
                            )
                        Spacer()
                        if pendingSoundId == sound.id {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(soundDisplayName(sound.id))
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)

                        Text(sound.id)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    HStack(spacing: 12) {
                        Label("\(sound.size) bytes", systemImage: "tray.full")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !sound.transcript.isEmpty {
                            Label("Transcript", systemImage: "text.quote")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !sound.lipsync.isEmpty {
                            Label("Lip Sync", systemImage: "waveform")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(
                                    pendingSoundId == sound.id
                                        ? Color.blue.opacity(0.9) : Color.white.opacity(0.25),
                                    lineWidth: pendingSoundId == sound.id ? 3 : 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled(false)
        }

        private var emptyState: some View {
            VStack(spacing: 24) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 80, weight: .thin))
                    .foregroundStyle(.secondary)
                Text("No sounds available yet.")
                    .font(.title2.weight(.semibold))
                Text("Connect to the creature server and refresh to populate the soundboard.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Button {
                    Task { await refresh(force: true) }
                } label: {
                    Label("Import from Server", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 18)
                        .background(
                            Capsule()
                                .fill(.blue.opacity(0.7))
                        )
                        .foregroundStyle(.white)
                }
                .disabled(isRefreshing)
            }
        }

        private func refresh(force: Bool = false) async {
            if isRefreshing { return }
            if !force && !sounds.isEmpty { return }

            await MainActor.run {
                withAnimation { isRefreshing = true }
            }

            defer {
                Task { @MainActor in
                    withAnimation { isRefreshing = false }
                }
            }

            do {
                let importer = SoundImporter(modelContainer: modelContext.container)
                let result = await server.listSounds()
                switch result {
                case .success(let remoteSounds):
                    try await importer.upsertBatch(remoteSounds)
                    await MainActor.run {
                        presentToast("Sound library updated", kind: .success)
                    }
                case .failure(let error):
                    logger.error("Failed to fetch sounds: \(error.localizedDescription)")
                    await MainActor.run {
                        presentError(
                            "Unable to Load Sounds",
                            message: ServerError.detailedMessage(from: error)
                        )
                    }
                }
            } catch {
                logger.error("Importer error: \(error.localizedDescription)")
                await MainActor.run {
                    presentError("Unable to Save Sounds", message: error.localizedDescription)
                }
            }
        }

        private func triggerSound(_ sound: SoundModel) {
            let soundId = sound.id
            let displayName = soundDisplayName(soundId)
            Task { [soundId, displayName] in
                await MainActor.run {
                    pendingSoundId = soundId
                }

                let prepareResult = await audioManager.prepareAndArmSoundFile(fileName: soundId)
                switch prepareResult {
                case .success:
                    logger.info("Prepared \(soundId) for local playback on tvOS")
                    let startResult = audioManager.startArmedPreview(in: 0.1)
                    switch startResult {
                    case .success:
                        await MainActor.run {
                            if pendingSoundId == soundId {
                                pendingSoundId = nil
                            }
                            presentToast("Playing \(displayName)", kind: .success)
                        }
                    case .failure(let error):
                        logger.warning("Unable to start playback for \(soundId): \(error)")
                        await MainActor.run {
                            if pendingSoundId == soundId {
                                pendingSoundId = nil
                            }
                            presentError(
                                "Playback Error",
                                message: audioErrorMessage(error)
                            )
                        }
                    }

                case .failure(let error):
                    logger.warning(
                        "Unable to prepare sound \(soundId) for local playback: \(error)")
                    await MainActor.run {
                        if pendingSoundId == soundId {
                            pendingSoundId = nil
                        }
                        presentError(
                            "Unable to Play Sound",
                            message: audioErrorMessage(error)
                        )
                    }
                }
            }
        }

        private func audioErrorMessage(_ error: AudioError) -> String {
            switch error {
            case .fileNotFound(let message),
                .noAccess(let message),
                .systemError(let message),
                .failedToLoad(let message):
                return message
            }
        }

        @MainActor
        private func presentError(_ title: String, message: String) {
            alertDescriptor = TVAlertDescriptor(title: title, message: message)
        }

        @MainActor
        private func presentToast(_ message: String, kind: TVStatusToast.Kind) {
            toastTask?.cancel()
            let newToast = TVStatusToast(kind: kind, message: message)
            withAnimation { toast = newToast }
            toastTask = Task { [newToastId = newToast.id] in
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                await MainActor.run {
                    if toast?.id == newToastId {
                        withAnimation { toast = nil }
                    }
                }
            }
        }

        private func soundDisplayName(_ identifier: String) -> String {
            if let dotIndex = identifier.lastIndex(of: ".") {
                let base = identifier[..<dotIndex]
                return base.replacingOccurrences(of: "_", with: " ").capitalized
            }
            return identifier.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
#endif
