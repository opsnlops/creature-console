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
        /// Where a `creature-cli network rtp-listen` relay lives — persisted per machine, since
        /// which Pi bridges the animatronic VLAN depends on where this machine is sitting.
        var relayHost: String = UserDefaults.standard.string(forKey: "spatialRelayHost") ?? "" {
            didSet { UserDefaults.standard.set(relayHost, forKey: "spatialRelayHost") }
        }
        var relayPort: Int = {
            let stored = UserDefaults.standard.integer(forKey: "spatialRelayPort")
            return stored == 0 ? 1964 : stored
        }()
        {
            didSet { UserDefaults.standard.set(relayPort, forKey: "spatialRelayPort") }
        }
        var selectedAnimationID: String?
        var isLooping = false {
            didSet {
                simulationSource?.setLooping(isLooping)
            }
        }
        /// Owns the stages on the server and the working copy being edited. The renderer follows
        /// every local edit so a drag is audible immediately, even though saving is deliberate.
        let store = StageStore()

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
        @ObservationIgnored private var knownCreatures: [StageCreature] = []

        init() {
            pathMonitor.pathUpdateHandler = { [weak self] path in
                let options = SACNInterfaceCatalog.interfaceOptions(from: path)
                Task { @MainActor [weak self] in
                    self?.updateInterfaces(options)
                }
            }
            pathMonitor.start(queue: pathQueue)

            store.onStageChanged = { [weak self] stage in
                self?.renderer?.update(stage: stage)
            }
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

        /// The stage being edited, or `nil` when the server has none yet.
        var stage: Stage? { store.stage }

        var placements: [StagePlacement] { store.stage?.placements ?? [] }

        var selectedPlacement: StagePlacement? {
            placements.first { $0.creatureID == selectedCreatureID }
        }

        /// What to call a placed creature: the live name when the creature list has loaded, and the
        /// name cached in the stage document otherwise. The cache exists so a stage renders before
        /// (or without) that list; it is not the source of truth.
        func displayName(for placement: StagePlacement) -> String {
            if let live = knownCreatures.first(where: { $0.id == placement.creatureID })?.name,
                !live.isEmpty
            {
                return live
            }
            return placement.creatureName.isEmpty ? placement.creatureID : placement.creatureName
        }

        /// Creatures with a usable audio lane that aren't on this stage yet.
        var creaturesOffStage: [StageCreature] {
            let placed = Set(placements.map(\.creatureID))
            return knownCreatures.filter {
                (1...16).contains($0.audioChannel) && !placed.contains($0.id)
            }
        }

        func loadStages() async {
            await store.load()
            store.noteKnownCreatures(knownCreatures)
            ensureSelection()
        }

        /// Track the creature list without touching the stage's geometry.
        ///
        /// Deliberately does not place newly-seen creatures: a stage is a server document whose
        /// `updated_at` invalidates every animation rendered against it, so merely opening this
        /// view must never dirty it. Off-stage creatures are offered explicitly instead.
        func reconcileCreatures(_ creatures: [StageCreature]) {
            knownCreatures = creatures
            store.noteKnownCreatures(creatures)
            ensureSelection()
        }

        func addCreatureToStage(id: String) {
            guard !isActive, !isPreparing else {
                return
            }
            guard let creature = knownCreatures.first(where: { $0.id == id }) else {
                return
            }
            store.addCreature(creature)
            selectedCreatureID = id
        }

        func removeCreatureFromStage(id: String) {
            guard !isActive, !isPreparing else {
                return
            }
            store.removeCreature(id: id)
            if selectedCreatureID == id {
                selectedCreatureID = placements.first?.creatureID
            }
        }

        func updatePlacement(
            id: String,
            _ update: (inout StagePlacement) -> Void
        ) {
            store.updatePlacement(creatureID: id, update)
        }

        private func ensureSelection() {
            if !placements.contains(where: { $0.creatureID == selectedCreatureID }) {
                selectedCreatureID = placements.first?.creatureID
            }
        }

        func start(simulations: [SpatialSimulationSelection]) async {
            stop()
            guard let stage = store.stage else {
                fail("Choose or create a stage first.")
                return
            }
            let channels = Set(stage.placements.map(\.audioChannel))
            guard !channels.isEmpty else {
                fail("Assign audio channels 1–16 to at least one creature.")
                return
            }
            guard channels.count == stage.placements.count else {
                fail("Each staged creature needs a unique audio channel.")
                return
            }

            isPreparing = true
            diagnostics.state = .starting
            let token = UUID()
            startToken = token

            do {
                let renderer = try SpatialAudioRenderer(channels: channels)
                renderer.update(stage: stage)

                switch inputMode {
                case .live, .liveRelay:
                    let transport: SpatialLiveTransport
                    if inputMode == .live {
                        guard
                            let selectedInterface = interfaces.first(where: {
                                $0.id == selectedInterfaceID
                            })
                        else {
                            throw SpatialStageViewModelError.noNetworkInterface
                        }
                        transport = .multicast(selectedInterface.nwInterface)
                    } else {
                        let host = relayHost.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !host.isEmpty else {
                            throw SpatialStageViewModelError.noRelayHost
                        }
                        guard (1...65535).contains(relayPort) else {
                            throw SpatialStageViewModelError.invalidRelayPort
                        }
                        transport = .relay(host: host, port: UInt16(relayPort))
                    }
                    let source = try SpatialLiveAudioSource(
                        renderer: renderer,
                        channels: channels,
                        monitoringDelayMilliseconds: stage.audio.monitoringDelayMilliseconds,
                        commonPlayoutDelayMilliseconds: stage.audio
                            .commonPlayoutDelayMilliseconds,
                        onDiagnostics: diagnosticsHandler(for: token)
                    )
                    try source.start(transport: transport)
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
        case noRelayHost
        case invalidRelayPort

        var errorDescription: String? {
            switch self {
            case .noNetworkInterface:
                "Choose the network interface connected to the creature audio network."
            case .noSimulationSelected:
                "Choose a multitrack animation to simulate."
            case .noRelayHost:
                "Enter the address of a machine running 'creature-cli network rtp-listen'."
            case .invalidRelayPort:
                "The relay port must be between 1 and 65535."
            }
        }
    }
#endif
