#if os(iOS)
    import AVFAudio
    import Common
    import SwiftData
    import SwiftUI

    /// Live relay monitoring and local simulation for iPhone and iPad. Geometry remains authored
    /// under Stages; this surface is deliberately a read-only listener optimized for headphones.
    struct IOSSpatialStageView: View {
        @Query(sort: \StageModel.title, order: .forward)
        private var stageModels: [StageModel]
        @Query(sort: \AnimationMetadataModel.title, order: .forward)
        private var animations: [AnimationMetadataModel]

        @AppStorage("relayHost") private var relayHost = "10.69.66.1"
        @AppStorage("audioRelayPort") private var relayPort = 1964
        @AppStorage("spatialHeadTrackingEnabled") private var headTrackingEnabled = true

        @State private var monitor = RelaySpatialStageMonitor()
        @State private var inputMode = SpatialStageInputMode.liveRelay
        @State private var selectedStageID: StageIdentifier?
        @State private var selectedAnimationID: AnimationIdentifier?
        @State private var selectedCreatureID: CreatureIdentifier?
        @State private var isLooping = false
        @State private var outputDescription = "Checking audio output…"
        @State private var errorMessage: String?
        @State private var showError = false

        private var selectedStage: Stage? {
            selectedStageID.flatMap { id in
                stageModels.first { $0.id == id }
            }?.toDTO()
        }

        private var simulations: [SpatialSimulationSelection] {
            animations
                .filter {
                    $0.multitrackAudio
                        && !$0.soundFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .map {
                    SpatialSimulationSelection(
                        id: $0.id,
                        title: $0.title.isEmpty ? $0.id : $0.title,
                        soundFile: $0.soundFile
                    )
                }
        }

        private var selectedSimulation: SpatialSimulationSelection? {
            simulations.first { $0.id == selectedAnimationID }
        }

        var body: some View {
            Group {
                if stageModels.isEmpty {
                    ContentUnavailableView {
                        Label("No Stages", systemImage: "square.on.square.dashed")
                    } description: {
                        Text("Create a stage first, then return here to listen to its audio.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            controls

                            if let selectedStage {
                                StageMapView(
                                    placements: selectedStage.placements,
                                    selectedCreatureID: $selectedCreatureID,
                                    displayName: displayName(for:),
                                    signalLevel: signalLevel(for:),
                                    channelHelp: diagnosticsHelp(for:)
                                )
                                .aspectRatio(1, contentMode: .fit)
                                .frame(minHeight: 340)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Spatial Stage")
            .alert("Spatial Playback Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .task {
                chooseDefaultStage()
                chooseDefaultSimulation()
                refreshOutputDescription()
            }
            .onChange(of: stageModels.map(\.id)) { _, _ in
                chooseDefaultStage()
            }
            .onChange(of: simulations) { _, _ in
                chooseDefaultSimulation()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            ) { _ in
                refreshOutputDescription()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification
                )
            ) { _ in
                refreshOutputDescription()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: AVAudioSession.renderingModeChangeNotification
                )
            ) { _ in
                refreshOutputDescription()
            }
            .onDisappear {
                monitor.stop()
            }
        }

        private var controls: some View {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Input", selection: $inputMode) {
                    ForEach([SpatialStageInputMode.liveRelay, .simulation]) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(monitor.isRunning)

                Picker("Stage", selection: $selectedStageID) {
                    Text("Choose a stage").tag(StageIdentifier?.none)
                    ForEach(stageModels) { stage in
                        Text(stage.title.isEmpty ? "(untitled)" : stage.title)
                            .tag(Optional(stage.id))
                    }
                }
                .disabled(monitor.isRunning)

                if inputMode == .simulation {
                    Picker("Animation", selection: $selectedAnimationID) {
                        Text("Choose a 17-channel animation").tag(AnimationIdentifier?.none)
                        ForEach(simulations) { simulation in
                            Text(simulation.title).tag(Optional(simulation.id))
                        }
                    }
                    .disabled(monitor.isRunning)

                    Toggle("Loop", isOn: $isLooping)
                        .onChange(of: isLooping) { _, newValue in
                            monitor.setLooping(newValue)
                        }
                        .disabled(monitor.diagnostics.state == .starting)
                }

                Toggle(isOn: $headTrackingEnabled) {
                    Label("Head Tracking", systemImage: "airpodsmax")
                }
                .disabled(monitor.isRunning)

                LabeledContent("Output") {
                    Text(outputDescription)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                status

                if inputMode == .simulation, monitor.diagnostics.simulationDuration > 0 {
                    simulationTransport
                }

                Button {
                    togglePlayback()
                } label: {
                    Label(
                        monitor.isRunning
                            ? "Stop"
                            : inputMode == .simulation ? "Play Simulation" : "Start Monitoring",
                        systemImage: monitor.isRunning ? "stop.fill" : "headphones"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.isRunning ? .red : .accentColor)
                .disabled(!monitor.isRunning && cannotStart)

                Text(inputDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }

        private var status: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(monitor.diagnostics.state.label)
                Spacer()
                if monitor.isRunning, inputMode == .liveRelay {
                    Text("\(Int(monitor.diagnostics.bufferedMilliseconds.rounded())) ms buffered")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }

        private var simulationTransport: some View {
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { monitor.diagnostics.simulationPosition },
                        set: { monitor.seek(to: $0) }
                    ),
                    in: 0...monitor.diagnostics.simulationDuration
                )

                HStack {
                    Text(
                        "\(formatted(monitor.diagnostics.simulationPosition)) / "
                            + formatted(monitor.diagnostics.simulationDuration)
                    )
                    .monospacedDigit()
                    Spacer()
                    Button {
                        monitor.setPaused(monitor.diagnostics.state != .paused)
                    } label: {
                        Label(
                            monitor.diagnostics.state == .paused ? "Resume" : "Pause",
                            systemImage: monitor.diagnostics.state == .paused
                                ? "play.fill" : "pause.fill"
                        )
                    }
                    .disabled(!monitor.isRunning)
                }
                .font(.caption)
            }
        }

        private var cannotStart: Bool {
            selectedStage == nil
                || (inputMode == .liveRelay
                    && relayHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                || (inputMode == .simulation && selectedSimulation == nil)
        }

        private var inputDescription: String {
            if inputMode == .simulation {
                return
                    "Simulation downloads the selected multitrack WAV and plays it only on this iPhone or iPad. It does not start the creature animation."
            }
            return
                "Live audio arrives through \(relayHost):\(relayPort). Change the relay under Settings › Network Monitors."
        }

        private var statusColor: Color {
            switch monitor.diagnostics.state {
            case .playing:
                .green
            case .starting, .waitingForAudio:
                .orange
            case .paused:
                .yellow
            case .failed:
                .red
            case .stopped:
                .secondary
            }
        }

        private func chooseDefaultStage() {
            guard
                selectedStageID == nil
                    || !stageModels.contains(where: { $0.id == selectedStageID })
            else {
                return
            }
            selectedStageID = stageModels.first?.id
        }

        private func chooseDefaultSimulation() {
            guard
                selectedAnimationID == nil
                    || !simulations.contains(where: { $0.id == selectedAnimationID })
            else {
                return
            }
            selectedAnimationID = simulations.first?.id
        }

        private func togglePlayback() {
            if monitor.isRunning {
                monitor.stop()
            } else if inputMode == .liveRelay {
                startMonitoring()
            } else {
                Task { await startSimulation() }
            }
        }

        private func startMonitoring() {
            guard let selectedStage else { return }
            do {
                try monitor.start(
                    stage: selectedStage,
                    host: relayHost,
                    port: relayPort,
                    headTrackingEnabled: headTrackingEnabled
                )
                refreshOutputDescription()
            } catch {
                present(error)
            }
        }

        private func startSimulation() async {
            guard let selectedStage, let selectedSimulation else { return }
            do {
                try await monitor.startSimulation(
                    stage: selectedStage,
                    soundFile: selectedSimulation.soundFile,
                    headTrackingEnabled: headTrackingEnabled,
                    looping: isLooping
                )
                refreshOutputDescription()
            } catch is CancellationError {
                return
            } catch {
                present(error)
            }
        }

        private func present(_ error: any Error) {
            errorMessage = ServerError.detailedMessage(from: error)
            showError = true
        }

        private func displayName(for placement: StagePlacement) -> String {
            placement.creatureName.isEmpty ? placement.creatureID : placement.creatureName
        }

        private func signalLevel(for channel: Int) -> Double {
            guard monitor.diagnostics.state == .playing else { return 0 }
            let level =
                monitor.diagnostics.channels.first { $0.channel == channel }?.level ?? 0
            return (SpatialAudioLevel.meterLevel(for: level) * 24).rounded() / 24
        }

        private func diagnosticsHelp(for channel: Int) -> String {
            guard
                let diagnostics = monitor.diagnostics.channels.first(where: {
                    $0.channel == channel
                })
            else {
                return "Audio channel \(channel)"
            }
            if inputMode == .simulation {
                return "Audio channel \(channel)"
            }
            return "Channel \(channel): \(diagnostics.packetsReceived) packets"
        }

        private func refreshOutputDescription() {
            let session = AVAudioSession.sharedInstance()
            guard let output = session.currentRoute.outputs.first else {
                outputDescription = "No audio route"
                return
            }
            let spatialDescription: String
            if output.isSpatialAudioEnabled, headTrackingEnabled {
                spatialDescription = "Spatial Audio · head tracked"
            } else if output.isSpatialAudioEnabled {
                spatialDescription = "Spatial Audio · fixed"
            } else {
                spatialDescription = "fixed spatial mix"
            }
            outputDescription = "\(output.portName) · \(spatialDescription)"
        }

        private func formatted(_ time: TimeInterval) -> String {
            let seconds = max(Int(time), 0)
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }

    }
#endif
