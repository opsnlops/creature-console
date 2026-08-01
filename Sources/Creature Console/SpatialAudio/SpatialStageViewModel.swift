#if os(macOS)
    import Common
    import Foundation
    import Network
    import Observation

    struct SpatialSimulationSelection: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let soundFile: String
    }

    @MainActor
    @Observable
    final class SpatialStageViewModel {
        var inputMode: SpatialStageInputMode = .simulation
        var interfaces: [SACNInterface] = []
        var selectedInterfaceID: String?
        var selectedAnimationID: String?
        var isLooping = false {
            didSet {
                simulationSource?.setLooping(isLooping)
            }
        }
        var layout = SpatialStageLayoutStore.load() {
            didSet {
                SpatialStageLayoutStore.save(layout)
                renderer?.update(layout: layout)
            }
        }
        private(set) var diagnostics = SpatialStageDiagnostics()
        private(set) var isPreparing = false
        var selectedCreatureID: String?

        @ObservationIgnored private let pathMonitor = NWPathMonitor()
        @ObservationIgnored private let pathQueue = DispatchQueue(
            label: "io.opsnlops.CreatureConsole.SpatialStagePathMonitor"
        )
        @ObservationIgnored private var renderer: SpatialAudioRenderer?
        @ObservationIgnored private var liveSource: SpatialLiveAudioSource?
        @ObservationIgnored private var simulationSource: SpatialSimulationAudioSource?
        @ObservationIgnored private var startToken = UUID()
        @ObservationIgnored private var knownCreatures: [SpatialStageCreature] = []

        init() {
            pathMonitor.pathUpdateHandler = { [weak self] path in
                let options = SACNInterfaceCatalog.interfaceOptions(from: path)
                Task { @MainActor [weak self] in
                    self?.updateInterfaces(options)
                }
            }
            pathMonitor.start(queue: pathQueue)
        }

        deinit {
            pathMonitor.cancel()
            liveSource?.stop()
            simulationSource?.stop()
        }

        var isActive: Bool {
            switch diagnostics.state {
            case .stopped, .failed:
                false
            case .starting, .waitingForAudio, .playing, .paused:
                true
            }
        }

        var isPaused: Bool {
            diagnostics.state == .paused
        }

        var selectedPlacement: SpatialStagePlacement? {
            layout.placements.first { $0.id == selectedCreatureID }
        }

        func reconcileCreatures(_ creatures: [SpatialStageCreature]) {
            knownCreatures = creatures
            var updated = layout
            updated.reconcile(with: creatures)
            guard updated != layout else {
                return
            }
            layout = updated
            if !updated.placements.contains(where: { $0.id == selectedCreatureID }) {
                selectedCreatureID = updated.placements.first?.id
            }
        }

        func removeCreatureFromStage(id: String) {
            guard !isActive, !isPreparing else {
                return
            }
            var updated = layout
            updated.removeCreature(id: id)
            guard updated != layout else {
                return
            }
            layout = updated
            if selectedCreatureID == id {
                selectedCreatureID = updated.placements.first?.id
            }
        }

        func restoreCreatureToStage(id: String) {
            guard !isActive, !isPreparing else {
                return
            }
            var updated = layout
            updated.restoreCreature(id: id, from: knownCreatures)
            guard updated != layout else {
                return
            }
            layout = updated
            selectedCreatureID = id
        }

        func updatePlacement(
            id: String,
            _ update: (inout SpatialStagePlacement) -> Void
        ) {
            guard let index = layout.placements.firstIndex(where: { $0.id == id }) else {
                return
            }
            var updated = layout
            update(&updated.placements[index])
            layout = updated
        }

        func start(simulations: [SpatialSimulationSelection]) async {
            stop()
            let channels = Set(layout.placements.map(\.audioChannel))
            guard !channels.isEmpty else {
                fail("Assign audio channels 1–16 to at least one creature.")
                return
            }
            guard channels.count == layout.placements.count else {
                fail("Each staged creature needs a unique audio channel.")
                return
            }

            isPreparing = true
            diagnostics.state = .starting
            let token = UUID()
            startToken = token

            do {
                let renderer = try SpatialAudioRenderer(channels: channels)
                renderer.update(layout: layout)

                switch inputMode {
                case .live:
                    guard
                        let selectedInterface = interfaces.first(where: {
                            $0.id == selectedInterfaceID
                        })
                    else {
                        throw SpatialStageViewModelError.noNetworkInterface
                    }
                    let source = try SpatialLiveAudioSource(
                        renderer: renderer,
                        channels: channels,
                        monitoringDelayMilliseconds: layout.monitoringDelayMilliseconds,
                        commonPlayoutDelayMilliseconds: layout
                            .commonPlayoutDelayMilliseconds,
                        onDiagnostics: diagnosticsHandler(for: token)
                    )
                    try source.start(interface: selectedInterface.nwInterface)
                    guard startToken == token else {
                        source.stop()
                        return
                    }
                    self.renderer = renderer
                    liveSource = source

                case .simulation:
                    guard
                        let selection = simulations.first(where: {
                            $0.id == selectedAnimationID
                        })
                    else {
                        throw SpatialStageViewModelError.noSimulationSelected
                    }
                    let fileURL = try await SpatialSimulationCache.shared.download(
                        soundFile: selection.soundFile
                    )
                    try Task.checkCancellation()
                    guard startToken == token else {
                        return
                    }
                    let source = try SpatialSimulationAudioSource(
                        renderer: renderer,
                        fileURL: fileURL,
                        channels: channels,
                        onDiagnostics: diagnosticsHandler(for: token)
                    )
                    self.renderer = renderer
                    simulationSource = source
                    source.start(looping: isLooping)
                }
            } catch is CancellationError {
                diagnostics.state = .stopped
            } catch {
                fail(error.localizedDescription)
            }
            if startToken == token {
                isPreparing = false
            }
        }

        func stop() {
            startToken = UUID()
            isPreparing = false
            liveSource?.stop()
            simulationSource?.stop()
            liveSource = nil
            simulationSource = nil
            renderer = nil
            diagnostics.state = .stopped
            diagnostics.bufferedMilliseconds = 0
            for index in diagnostics.channels.indices {
                diagnostics.channels[index].level = 0
            }
        }

        func togglePause() {
            guard inputMode == .simulation else {
                return
            }
            simulationSource?.setPaused(!isPaused)
        }

        func seek(to time: TimeInterval) {
            simulationSource?.seek(to: time)
        }

        private func diagnosticsHandler(
            for token: UUID
        ) -> @Sendable (SpatialStageDiagnostics) -> Void {
            { [weak self] diagnostics in
                Task { @MainActor [weak self] in
                    guard self?.startToken == token else {
                        return
                    }
                    self?.diagnostics = diagnostics
                }
            }
        }

        private func updateInterfaces(_ newInterfaces: [SACNInterface]) {
            interfaces = newInterfaces
            guard
                let selectedInterfaceID,
                newInterfaces.contains(where: { $0.id == selectedInterfaceID })
            else {
                self.selectedInterfaceID =
                    newInterfaces.first(where: {
                        $0.type == .wiredEthernet
                    })?.id ?? newInterfaces.first?.id
                return
            }
        }

        private func fail(_ message: String) {
            isPreparing = false
            diagnostics.state = .failed(message)
        }
    }

    enum SpatialStageViewModelError: LocalizedError {
        case noNetworkInterface
        case noSimulationSelected

        var errorDescription: String? {
            switch self {
            case .noNetworkInterface:
                "Choose the network interface connected to the creature audio network."
            case .noSimulationSelected:
                "Choose a multitrack animation to simulate."
            }
        }
    }
#endif
