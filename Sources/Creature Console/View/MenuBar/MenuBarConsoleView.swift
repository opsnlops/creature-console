#if os(macOS)
    import Common
    import PlaylistRuntime
    import SwiftData
    import SwiftUI

    #if canImport(AppKit)
        import AppKit
    #endif

    struct MenuBarConsoleView: View {

        @StateObject private var viewModel = MenuBarConsoleViewModel()
        @AppStorage("menubarSelectedCreatureId") private var storedCreatureId: CreatureIdentifier =
            ""
        @AppStorage("activeUniverse") private var activeUniverse: Int = 1
        @PlaylistResumePreference private var resumePlaylistAfterPlayback: Bool

        @Query(sort: \CreatureModel.name, order: .forward)
        private var creatures: [CreatureModel]

        @State private var showAllPrepared = false

        private let timestampFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter
        }()

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                connectionSection
                Divider()
                adHocSection
                if !viewModel.preparedAnimations.isEmpty {
                    preparedSection
                    Divider()
                }
                playlistsSection
                Divider()
                healthSection
                if !viewModel.jobInfos.isEmpty {
                    Divider()
                    jobsSection
                }
                if let error = viewModel.errorMessage, !error.isEmpty {
                    Divider()
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .frame(width: 360)
            .task {
                await AppBootstrapper.shared.startIfNeeded()
                initializeSelection()
                viewModel.start(selectedCreatureId: storedCreatureId)
            }
            .onChange(of: creatures) { _, _ in
                initializeSelection()
            }
            .onChange(of: storedCreatureId) { _, newValue in
                viewModel.updateSelectedCreature(newValue)
            }
        }

        private var selectedCreatureName: String? {
            creatures.first(where: { $0.id == storedCreatureId })?.name
        }
    }

    extension MenuBarConsoleView {
        fileprivate var connectionSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 12, height: 12)
                    Text(viewModel.connectionState.description)
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.reconnect()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .help("Reconnect to server")
                }
                if creatures.isEmpty {
                    Text("Creatures will appear after sync.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Creature", selection: $storedCreatureId) {
                        ForEach(creatures) { creature in
                            Text(creature.name).tag(creature.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }

        fileprivate var adHocSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ad-hoc animation")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await viewModel.refreshPreparedAnimations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh prepared animations")
                }

                TextField(placeholderText, text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .textFieldStyle(.roundedBorder)

                Toggle(
                    "Resume playlist after playback",
                    isOn: $resumePlaylistAfterPlayback
                )

                HStack {
                    Button("Play Now") {
                        Task {
                            await viewModel.playInstant(resumePlaylist: resumePlaylistAfterPlayback)
                        }
                    }
                    Button("Cue") {
                        Task {
                            await viewModel.cueAdHoc(resumePlaylist: resumePlaylistAfterPlayback)
                        }
                    }
                }
            }
        }

        fileprivate var preparedSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Prepared Animations")
                    .font(.headline)
                let animations =
                    showAllPrepared
                    ? viewModel.preparedAnimations
                    : Array(viewModel.preparedAnimations.prefix(5))
                ForEach(animations) { animation in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(animation.metadata.title)
                                .font(.subheadline)
                            if let date = animation.createdAt {
                                Text(timestampFormatter.string(from: date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Trigger") {
                            Task {
                                await viewModel.triggerPrepared(
                                    animationId: animation.animationId,
                                    resumePlaylist: resumePlaylistAfterPlayback
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                if viewModel.preparedAnimations.count > 5 {
                    Button(showAllPrepared ? "Show Less" : "Show All") {
                        showAllPrepared.toggle()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        fileprivate var playlistsSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Playlists")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await viewModel.refreshPlaylists() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh playlists")
                }

                if viewModel.playlists.isEmpty {
                    Text("No playlists available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Menu("Start Playlist") {
                        ForEach(viewModel.playlists) { playlist in
                            Button(playlist.name) {
                                Task {
                                    await viewModel.startPlaylist(
                                        playlist,
                                        universe: clampedUniverse
                                    )
                                }
                            }
                        }
                    }
                    .menuStyle(.borderedButton)
                }

                Button("Stop Active Playlist") {
                    Task {
                        await viewModel.stopPlaylist(universe: clampedUniverse)
                    }
                }
                .buttonStyle(.bordered)
            }
        }

        fileprivate var healthSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Creature Health")
                    .font(.headline)
                if let power = viewModel.latestMotorInPower,
                    let voltage = viewModel.latestMotorInVoltage,
                    let updated = viewModel.lastUpdated
                {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                        GridRow {
                            Text("Motor In Power")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f W", power))
                        }
                        GridRow {
                            Text("Motor In Voltage")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f V", voltage))
                        }
                        GridRow {
                            Text("Updated")
                                .foregroundStyle(.secondary)
                            Text(timestampFormatter.string(from: updated))
                        }
                    }
                } else {
                    Text("Waiting for sensor data…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        fileprivate var jobsSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Jobs")
                    .font(.headline)
                ForEach(viewModel.jobInfos) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.jobType.rawValue)
                            .font(.subheadline)
                        Text("Status: \(job.status.rawValue)")
                            .font(.caption)
                        if let progress = job.progressPercentage {
                            ProgressView(value: progress, total: 100)
                                .progressViewStyle(.linear)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
        }

        fileprivate var connectionColor: Color {
            switch viewModel.connectionState {
            case .connected:
                return .green
            case .connecting, .reconnecting:
                return .orange
            case .closing:
                return .yellow
            case .disconnected:
                return .red
            }
        }

        private var placeholderText: String {
            if let name = selectedCreatureName, !name.isEmpty {
                return "What should \(name) say?"
            } else {
                return "What should the creature say?"
            }
        }

        private var clampedUniverse: UniverseIdentifier {
            UniverseIdentifier(max(1, activeUniverse))
        }

        private func initializeSelection() {
            if !storedCreatureId.isEmpty,
                creatures.contains(where: { $0.id == storedCreatureId })
            {
                return
            }

            if let first = creatures.first {
                storedCreatureId = first.id
            }
        }
    }
#endif
