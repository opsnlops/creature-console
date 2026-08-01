#if os(macOS)
    import SwiftData
    import SwiftUI

    struct SpatialStageView: View {
        @Query(sort: \CreatureModel.name) private var creatures: [CreatureModel]
        @Query(sort: \AnimationMetadataModel.title)
        private var animations: [AnimationMetadataModel]
        @State private var viewModel = SpatialStageViewModel()

        private var stageCreatures: [SpatialStageCreature] {
            creatures.map {
                SpatialStageCreature(id: $0.id, name: $0.name, audioChannel: $0.audioChannel)
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

        private var removedStageCreatures: [SpatialStageCreature] {
            stageCreatures.filter { viewModel.layout.excludedCreatureIDs.contains($0.id) }
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
            .onAppear {
                viewModel.reconcileCreatures(stageCreatures)
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

        private var inspector: some View {
            @Bindable var model = viewModel
            return Form {
                Section("Stage") {
                    LabeledContent("Width") {
                        Text("\(viewModel.layout.stageWidth, specifier: "%.1f") m")
                    }
                    Slider(
                        value: $model.layout.stageWidth,
                        in: 4...20
                    )
                    LabeledContent("Depth") {
                        Text("\(viewModel.layout.stageDepth, specifier: "%.1f") m")
                    }
                    Slider(
                        value: $model.layout.stageDepth,
                        in: 3...15
                    )
                }

                Section("Monitoring") {
                    Stepper(
                        "\(viewModel.layout.monitoringDelayMilliseconds) ms RTP buffer",
                        value: $model.layout.monitoringDelayMilliseconds,
                        in: 10...250,
                        step: 10
                    )
                    .disabled(viewModel.isActive)

                    Stepper(
                        "\(viewModel.layout.commonPlayoutDelayMilliseconds) ms RTCP playout",
                        value: $model.layout.commonPlayoutDelayMilliseconds,
                        in: 20...250,
                        step: 10
                    )
                    .disabled(viewModel.isActive)

                    LabeledContent("BGM") {
                        Text("\(Int(viewModel.layout.backgroundMusicGain * 100))%")
                    }
                    Slider(
                        value: $model.layout.backgroundMusicGain,
                        in: 0...1
                    )
                    LabeledContent("Room") {
                        Text("\(Int(viewModel.layout.reverbBlend * 100))%")
                    }
                    Slider(
                        value: $model.layout.reverbBlend,
                        in: 0...0.5
                    )
                }

                if let placement = viewModel.selectedPlacement {
                    Section(placement.creatureName) {
                        LabeledContent("Audio channel", value: "\(placement.audioChannel)")
                        LabeledContent("Left / right") {
                            Text("\(placement.x, specifier: "%.1f") m")
                        }
                        Slider(
                            value: placementBinding(placement.id, \.x),
                            in: (-viewModel.layout.stageWidth / 2)...(viewModel.layout.stageWidth
                                / 2)
                        )
                        LabeledContent("Stage depth") {
                            Text("\(-placement.z, specifier: "%.1f") m")
                        }
                        Slider(
                            value: placementBinding(placement.id, \.z),
                            in: -viewModel.layout.stageDepth...0
                        )
                        LabeledContent("Gain") {
                            Text("\(Int(placement.gain * 100))%")
                        }
                        Slider(
                            value: placementBinding(placement.id, \.gain),
                            in: 0...1.5
                        )
                        Toggle(
                            "Muted",
                            isOn: Binding(
                                get: { viewModel.selectedPlacement?.isMuted ?? false },
                                set: { newValue in
                                    viewModel.updatePlacement(id: placement.id) {
                                        $0.isMuted = newValue
                                    }
                                }
                            )
                        )
                    }
                } else {
                    Section("Creature") {
                        Text("Select a creature on the stage to tune its position and gain.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !removedStageCreatures.isEmpty {
                    Section("Removed from Stage") {
                        ForEach(removedStageCreatures) { creature in
                            Button {
                                viewModel.restoreCreatureToStage(id: creature.id)
                            } label: {
                                Label(
                                    "Restore \(creature.name)",
                                    systemImage: "plus.circle"
                                )
                            }
                            .disabled(viewModel.isActive || viewModel.isPreparing)
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

        private func placementBinding(
            _ id: String,
            _ keyPath: WritableKeyPath<SpatialStagePlacement, Float>
        ) -> Binding<Float> {
            Binding(
                get: {
                    viewModel.layout.placements.first(where: { $0.id == id })?[keyPath: keyPath]
                        ?? 0
                },
                set: { value in
                    viewModel.updatePlacement(id: id) {
                        $0[keyPath: keyPath] = value
                    }
                }
            )
        }
    }

    private struct SpatialStageCanvas: View {
        @Environment(\.colorScheme) private var colorScheme
        @Bindable var viewModel: SpatialStageViewModel

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.indigo.opacity(0.18),
                                    Color.black.opacity(0.06),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    stageGrid
                    stageDiagnostics
                    listener

                    ForEach(viewModel.layout.placements) { placement in
                        creatureNode(placement)
                            .position(position(for: placement, in: proxy.size))
                            .simultaneousGesture(
                                DragGesture(coordinateSpace: .named("spatialStage"))
                                    .onChanged { value in
                                        move(placement, to: value.location, in: proxy.size)
                                    }
                            )
                    }
                }
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                Color.purple.opacity(0.5 * signalLevel(for: 17)),
                                lineWidth: 1 + 2 * signalLevel(for: 17)
                            )
                            .blur(radius: 1 + 5 * signalLevel(for: 17))
                    }
                }
                .coordinateSpace(name: "spatialStage")
                .animation(.linear(duration: 0.1), value: signalLevel(for: 17))
            }
        }

        private var stageGrid: some View {
            Canvas { context, size in
                var path = Path()
                for index in 1..<5 {
                    let x = size.width * CGFloat(index) / 5
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    let y = size.height * CGFloat(index) / 5
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.secondary.opacity(0.16)), lineWidth: 1)
            }
            .padding(1)
        }

        private var listener: some View {
            VStack(spacing: 3) {
                Image(systemName: "headphones")
                    .font(.title2)
                Text("You")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
            .allowsHitTesting(false)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

        private func creatureNode(_ placement: SpatialStagePlacement) -> some View {
            let level = signalLevel(for: placement.audioChannel)
            return VStack(spacing: 2) {
                Image(systemName: placement.isMuted ? "speaker.slash.fill" : "bird.fill")
                Text(placement.creatureName)
                    .lineLimit(1)
                Text("CH \(placement.audioChannel)")
                    .font(.caption2.monospacedDigit())
                    .opacity(0.7)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(
                placement.isMuted ? Color.secondary : creatureForegroundColor
            )
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(creatureSurfaceColor)
                    if viewModel.selectedCreatureID == placement.id {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.32))
                    }
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.3 * level))
                }
            }
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            Color.green.opacity(0.65 * level),
                            lineWidth: 1 + level
                        )
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            viewModel.selectedCreatureID == placement.id
                                ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: viewModel.selectedCreatureID == placement.id ? 2 : 1
                        )
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                viewModel.selectedCreatureID = placement.id
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                viewModel.selectedCreatureID = placement.id
            }
            .shadow(
                color: Color.green.opacity(0.5 * level),
                radius: 4 + 10 * level
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .help(diagnosticsHelp(for: placement.audioChannel))
            .contextMenu {
                Button("Remove from Stage", systemImage: "minus.circle") {
                    viewModel.removeCreatureFromStage(id: placement.id)
                }
                .disabled(viewModel.isActive || viewModel.isPreparing)
            }
        }

        private var creatureSurfaceColor: Color {
            switch colorScheme {
            case .dark:
                Color(red: 0.08, green: 0.08, blue: 0.09)
            case .light:
                Color(red: 0.96, green: 0.96, blue: 0.97)
            @unknown default:
                Color(red: 0.08, green: 0.08, blue: 0.09)
            }
        }

        private var creatureForegroundColor: Color {
            colorScheme == .dark ? .white : .black
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

        private func position(
            for placement: SpatialStagePlacement,
            in size: CGSize
        ) -> CGPoint {
            let normalizedX =
                CGFloat(placement.x / max(viewModel.layout.stageWidth, 0.1)) + 0.5
            let normalizedZ =
                1 + CGFloat(placement.z / max(viewModel.layout.stageDepth, 0.1))
            return CGPoint(
                x: min(max(normalizedX, 0.04), 0.96) * size.width,
                y: min(max(normalizedZ, 0.06), 0.9) * size.height
            )
        }

        private func move(
            _ placement: SpatialStagePlacement,
            to location: CGPoint,
            in size: CGSize
        ) {
            guard size.width > 0, size.height > 0 else {
                return
            }
            let clampedX = min(max(location.x / size.width, 0), 1)
            let clampedY = min(max(location.y / size.height, 0), 1)
            viewModel.updatePlacement(id: placement.id) {
                $0.x = (Float(clampedX) - 0.5) * viewModel.layout.stageWidth
                $0.z = (Float(clampedY) - 1) * viewModel.layout.stageDepth
            }
            viewModel.selectedCreatureID = placement.id
        }
    }
#endif
