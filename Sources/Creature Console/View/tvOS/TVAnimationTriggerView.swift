#if os(tvOS)
    import Common
    import OSLog
    import SwiftData
    import SwiftUI

    struct TVAnimationTriggerView: View {

        @Environment(\.modelContext) private var modelContext
        @Query(sort: \AnimationMetadataModel.title, order: .forward)
        private var animations: [AnimationMetadataModel]

        @AppStorage("activeUniverse") private var activeUniverse: UniverseIdentifier = 1

        private let creatureManager = CreatureManager.shared
        private let server = CreatureServerClient.shared
        private let logger = Logger(
            subsystem: "io.opsnlops.CreatureConsole", category: "TVAnimationTriggerView")

        @State private var isRefreshing = false
        @State private var pendingAction: PendingAction?
        @State private var resumePreferences: [AnimationIdentifier: Bool] = [:]
        @State private var alertDescriptor: TVAlertDescriptor?
        @State private var toast: TVStatusToast?
        @State private var toastTask: Task<Void, Never>?

        private var gridColumns: [GridItem] {
            [GridItem(.adaptive(minimum: 360, maximum: 460), spacing: 36, alignment: .top)]
        }

        var body: some View {
            ScrollView {
                if animations.isEmpty && !isRefreshing {
                    emptyState
                        .padding(.horizontal, 80)
                        .padding(.top, 120)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 36) {
                        ForEach(animations) { animation in
                            animationCard(for: animation)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 60)
                }
            }
            .background(Color.clear.ignoresSafeArea())
            .navigationTitle("Animations")
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
                    ProgressView("Updating animations…")
                        .font(.title2)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
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

        private func animationCard(for animation: AnimationMetadataModel) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    Image(systemName: "figure.socialdance")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.purple.opacity(0.75))
                        )
                    Spacer()
                    if pendingAction?.id == animation.id {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(animation.title.isEmpty ? "Untitled Animation" : animation.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)

                    Text(animation.id)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 12) {
                    Label("\(animation.numberOfFrames) frames", systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("\(animation.millisecondsPerFrame) ms", systemImage: "speedometer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !animation.soundFile.isEmpty {
                        Label(animation.soundFile, systemImage: "speaker.wave.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                if !animation.note.isEmpty {
                    Text(animation.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        Button {
                            triggerPlay(animation)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            triggerInterrupt(animation)
                        } label: {
                            Label("Interrupt", systemImage: "bolt.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Toggle(
                        "Resume playlist after animation",
                        isOn: resumeBinding(for: animation.id)
                    )
                    .toggleStyle(.switch)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(
                                pendingAction?.id == animation.id
                                    ? Color.purple.opacity(0.9) : Color.white.opacity(0.25),
                                lineWidth: pendingAction?.id == animation.id ? 3 : 1
                            )
                    )
            )
        }

        private var emptyState: some View {
            VStack(spacing: 24) {
                Image(systemName: "film")
                    .font(.system(size: 80, weight: .thin))
                    .foregroundStyle(.secondary)
                Text("No animations have been imported yet.")
                    .font(.title2.weight(.semibold))
                Text("Fetch the current library from the creature server to unlock these triggers.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Button {
                    Task { await refresh(force: true) }
                } label: {
                    Label("Import Animations", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 18)
                        .background(
                            Capsule()
                                .fill(.purple.opacity(0.75))
                        )
                        .foregroundStyle(.white)
                }
                .disabled(isRefreshing)
            }
        }

        private func refresh(force: Bool = false) async {
            if isRefreshing { return }
            if !force && !animations.isEmpty { return }

            await MainActor.run {
                withAnimation { isRefreshing = true }
            }

            defer {
                Task { @MainActor in
                    withAnimation { isRefreshing = false }
                }
            }

            do {
                let importer = AnimationMetadataImporter(modelContainer: modelContext.container)
                let result = await server.listAnimations()
                switch result {
                case .success(let remoteAnimations):
                    try await importer.upsertBatch(remoteAnimations)
                    await MainActor.run {
                        presentToast("Animation library updated", kind: .success)
                    }
                case .failure(let error):
                    logger.error("Failed to fetch animations: \(error.localizedDescription)")
                    await MainActor.run {
                        presentError(
                            "Unable to Load Animations",
                            message: ServerError.detailedMessage(from: error)
                        )
                    }
                }
            } catch {
                logger.error("Importer error: \(error.localizedDescription)")
                await MainActor.run {
                    presentError("Unable to Save Animations", message: error.localizedDescription)
                }
            }
        }

        private func triggerPlay(_ animation: AnimationMetadataModel) {
            let animationId = animation.id
            let displayTitle = animation.title.isEmpty ? animation.id : animation.title
            let universe = activeUniverse
            pendingAction = PendingAction(id: animationId, kind: .play)
            Task { [animationId, displayTitle, universe] in
                let result = await creatureManager.playStoredAnimationOnServer(
                    animationId: animationId,
                    universe: universe
                )
                await MainActor.run {
                    if pendingAction?.id == animationId {
                        pendingAction = nil
                    }

                    switch result {
                    case .success(let message):
                        logger.debug("Triggered animation \(animationId): \(message)")
                        presentToast("Playing \(displayTitle)", kind: .success)
                    case .failure(let error):
                        logger.warning(
                            "Unable to trigger animation \(animationId): \(error.localizedDescription)"
                        )
                        presentError(
                            "Unable to Play Animation",
                            message: ServerError.detailedMessage(from: error)
                        )
                    }
                }
            }
        }

        private func triggerInterrupt(_ animation: AnimationMetadataModel) {
            let animationId = animation.id
            let displayTitle = animation.title.isEmpty ? animation.id : animation.title
            let universe = activeUniverse
            let resumePlaylist = resumePreferences[animationId, default: true]
            pendingAction = PendingAction(id: animationId, kind: .interrupt)
            Task { [animationId, displayTitle, universe, resumePlaylist] in
                let result = await creatureManager.interruptWithAnimation(
                    animationId: animationId,
                    universe: universe,
                    resumePlaylist: resumePlaylist
                )
                await MainActor.run {
                    if pendingAction?.id == animationId {
                        pendingAction = nil
                    }

                    switch result {
                    case .success(let message):
                        logger.debug("Interrupted with animation \(animationId): \(message)")
                        presentToast("Interrupting with \(displayTitle)", kind: .info)
                    case .failure(let error):
                        logger.warning(
                            "Unable to interrupt animation \(animationId): \(error.localizedDescription)"
                        )
                        presentError(
                            "Unable to Interrupt",
                            message: ServerError.detailedMessage(from: error)
                        )
                    }
                }
            }
        }

        private func resumeBinding(for animationId: AnimationIdentifier) -> Binding<Bool> {
            Binding(
                get: { resumePreferences[animationId, default: true] },
                set: { resumePreferences[animationId] = $0 }
            )
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
    }

    private struct PendingAction: Equatable {
        enum Kind {
            case play
            case interrupt
        }

        let id: AnimationIdentifier
        let kind: Kind
    }

#endif
