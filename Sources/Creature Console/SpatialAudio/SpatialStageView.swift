#if os(macOS)
    import Common
    import SwiftData
    import SwiftUI

    struct SpatialStageView: View {
        @Query(sort: \CreatureModel.name) private var creatures: [CreatureModel]
        @Query(sort: \AnimationMetadataModel.title)
        private var animations: [AnimationMetadataModel]
        @State private var viewModel = SpatialStageViewModel()

        private var stageCreatures: [StageCreature] {
            creatures.map {
                StageCreature(id: $0.id, name: $0.name, audioChannel: $0.audioChannel)
            }
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

        var body: some View {
            VStack(spacing: 0) {
                transport
                Divider()
                HSplitView {
                    SpatialStageCanvas(viewModel: viewModel)
                        .frame(minWidth: 600, minHeight: 440)
                        .padding()

                    inspector
                        .frame(minWidth: 275, idealWidth: 310, maxWidth: 360)
                }
            }
            .navigationTitle("Spatial Stage")
            .task {
                viewModel.reconcileCreatures(stageCreatures)
                await viewModel.loadStages()
                chooseDefaultSimulation()
            }
            .onChange(of: stageCreatures) { _, newValue in
                viewModel.reconcileCreatures(newValue)
            }
            .onChange(of: simulations) { _, _ in
                chooseDefaultSimulation()
            }
            .onDisappear {
                viewModel.stop()
            }
        }

        private var transport: some View {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Picker("Input", selection: $viewModel.inputMode) {
                        ForEach(SpatialStageInputMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .disabled(viewModel.isActive || viewModel.isPreparing)

                    if viewModel.inputMode == .live {
                        Picker("Interface", selection: $viewModel.selectedInterfaceID) {
                            Text("Choose Interface").tag(String?.none)
                            ForEach(viewModel.interfaces) { interface in
                                Text(interface.displayName).tag(Optional(interface.id))
                            }
                        }
                        .frame(maxWidth: 380)
                        .disabled(viewModel.isActive || viewModel.isPreparing)
                    } else {
                        Picker("Animation", selection: $viewModel.selectedAnimationID) {
                            Text("Choose 17-channel WAV").tag(String?.none)
                            ForEach(simulations) { simulation in
                                Text(simulation.title).tag(Optional(simulation.id))
                            }
                        }
                        .frame(maxWidth: 380)
                        .disabled(viewModel.isActive || viewModel.isPreparing)
                    }

                    Spacer()

                    if viewModel.inputMode == .simulation {
                        Toggle("Loop", isOn: $viewModel.isLooping)
                            .toggleStyle(.switch)
                            .fixedSize()
                        Button {
                            viewModel.togglePause()
                        } label: {
                            Label(
                                viewModel.isPaused ? "Resume" : "Pause",
                                systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                            )
                        }
                        .disabled(!viewModel.isActive)
                    }

                    Button {
                        if viewModel.isActive || viewModel.isPreparing {
                            viewModel.stop()
                        } else {
                            Task {
                                await viewModel.start(simulations: simulations)
                            }
                        }
                    } label: {
                        Label(
                            viewModel.isActive || viewModel.isPreparing ? "Stop" : "Listen",
                            systemImage: viewModel.isActive || viewModel.isPreparing
                                ? "stop.fill" : "headphones"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(viewModel.diagnostics.state.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if viewModel.inputMode == .simulation,
                        viewModel.diagnostics.simulationDuration > 0
                    {
                        Slider(
                            value: Binding(
                                get: { viewModel.diagnostics.simulationPosition },
                                set: { viewModel.seek(to: $0) }
                            ),
                            in: 0...viewModel.diagnostics.simulationDuration
                        )
                        Text(
                            "\(formatted(viewModel.diagnostics.simulationPosition)) / "
                                + formatted(viewModel.diagnostics.simulationDuration)
                        )
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    } else {
                        Spacer()
                        Text(
                            "\(Int(viewModel.diagnostics.bufferedMilliseconds.rounded())) ms buffered"
                        )
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                }
                .font(.caption)
            }
            .padding()
        }

        /// The listening window's inspector. Deliberately read-only about geometry — a stage is
        /// authored in the Stages section of the sidebar, so there is exactly one editing surface
        /// and the two can't disagree about what's saved.
        private var inspector: some View {
            Form {
                Section("Stage") {
                    Picker("Stage", selection: stageSelection) {
                        Text("None").tag(StageIdentifier?.none)
                        ForEach(viewModel.store.stages) { stage in
                            Text(stage.title.isEmpty ? "(untitled)" : stage.title)
                                .tag(Optional(stage.id))
                        }
                    }
                    .disabled(viewModel.isActive || viewModel.isPreparing)

                    if case .failed(let message) = viewModel.store.loadState {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }

                    if viewModel.stage == nil {
                        Text("Create a stage under Stages in the main window to listen to one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Creatures", value: "\(viewModel.placements.count)")
                        Text("Positions and facings are edited under Stages in the main window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let placement = viewModel.selectedPlacement {
                    Section(viewModel.displayName(for: placement)) {
                        LabeledContent("Audio channel", value: "\(placement.audioChannel)")
                        LabeledContent("Height") {
                            Text("\(placement.y, specifier: "%+.2f") m").monospacedDigit()
                        }
                        LabeledContent("Left / right") {
                            Text("\(placement.x, specifier: "%+.2f") m").monospacedDigit()
                        }
                        LabeledContent("Front / back") {
                            Text("\(placement.z, specifier: "%+.2f") m").monospacedDigit()
                        }
                        LabeledContent("Facing") {
                            Text("\(placement.yaw, specifier: "%+.0f")°").monospacedDigit()
                        }
                        LabeledContent("Gain") {
                            Text(placement.isMuted ? "Muted" : "\(Int(placement.gain * 100))%")
                        }
                    }
                }

                Section {
                    Text(
                        "Simulation downloads the selected multitrack WAV and renders it only "
                            + "on this Mac. It does not start an animation or send play commands."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }


        private var statusColor: Color {
            switch viewModel.diagnostics.state {
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

        private func chooseDefaultSimulation() {
            guard
                viewModel.selectedAnimationID == nil
                    || !simulations.contains(where: { $0.id == viewModel.selectedAnimationID })
            else {
                return
            }
            viewModel.selectedAnimationID = simulations.first?.id
        }

        private func formatted(_ time: TimeInterval) -> String {
            let seconds = max(Int(time), 0)
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }

        private var stageSelection: Binding<StageIdentifier?> {
            Binding(
                get: { viewModel.stage?.id },
                set: { viewModel.store.select($0) }
            )
        }

    }

    /// The listening window's map: the shared stage canvas, read-only, with live audio meters
    /// and the RTP diagnostics overlaid on top.
    private struct SpatialStageCanvas: View {
        @Bindable var viewModel: SpatialStageViewModel

        var body: some View {
            StageMapView(
                placements: viewModel.placements,
                selectedCreatureID: $viewModel.selectedCreatureID,
                displayName: viewModel.displayName(for:),
                // No onMove: geometry is authored under Stages, not while listening.
                signalLevel: signalLevel(for:),
                channelHelp: diagnosticsHelp(for:)
            )
            .overlay(alignment: .top) { stageDiagnostics }
        }

        private var stageDiagnostics: some View {
            HStack(alignment: .top, spacing: 8) {
                Label("BGM", systemImage: "music.note")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Color.purple.opacity(0.12 + 0.45 * signalLevel(for: 17)),
                        in: .capsule
                    )
                    .shadow(
                        color: Color.purple.opacity(0.45 * signalLevel(for: 17)),
                        radius: 8 * signalLevel(for: 17)
                    )
                    .animation(.linear(duration: 0.1), value: signalLevel(for: 17))
                    .help("The pill follows background-music channel 17.")

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(
                        "Output latency "
                            + "\(Int(viewModel.diagnostics.outputLatencyMilliseconds.rounded())) ms"
                    )
                    if viewModel.inputMode == .live {
                        Text(liveTimingDescription)
                        if viewModel.diagnostics.outputUnderruns > 0 {
                            Text("\(viewModel.diagnostics.outputUnderruns) output underruns")
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }
            .font(.caption2)
            .padding(10)
            .allowsHitTesting(false)
        }

        private var liveTimingDescription: String {
            switch viewModel.diagnostics.liveTimingMode {
            case .waiting:
                return "Waiting for synchronized RTCP"
            case .rtcp:
                if let lateness = viewModel.diagnostics.rtcpStartLatenessMilliseconds,
                    let delay = viewModel.diagnostics.rtcpPlayoutDelayMilliseconds
                {
                    return String(
                        format: "RTCP synchronized (%+.1f ms, %.0f ms playout)",
                        lateness,
                        delay
                    )
                }
                return "RTCP synchronized"
            case .arrivalFallback:
                return "Arrival-timed fallback"
            }
        }

        private func signalLevel(for channel: Int) -> Double {
            guard viewModel.diagnostics.state == .playing else {
                return 0
            }
            let level =
                viewModel.diagnostics.channels.first(where: { $0.channel == channel })?.level ?? 0
            return SpatialAudioLevel.meterLevel(for: level)
        }

        private func diagnosticsHelp(for channel: Int) -> String {
            guard
                let diagnostics = viewModel.diagnostics.channels.first(where: {
                    $0.channel == channel
                })
            else {
                return "Audio channel \(channel)"
            }
            return
                "Channel \(channel): \(diagnostics.packetsReceived) packets, "
                + "\(diagnostics.concealedFrames) concealed, \(diagnostics.fecFrames) FEC"
        }
    }
#endif
