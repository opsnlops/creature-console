import Common
import SwiftData
import SwiftUI

/// Live show monitoring from the couch: connect to a `creature-cli network rtp-listen` relay
/// (a Pi wired to the animatronic VLAN), pick a stage, and hear what the birds are playing
/// *right now*, positioned in space, out HDMI as discrete multichannel LPCM.
///
/// tvOS can't join multicast groups, so the relay isn't a convenience here — it's the only
/// possible transport. The pipeline behind it is the exact one the Mac's Spatial Stage window
/// uses; only the packet source differs.
struct TVLiveStageView: View {

    @Query(sort: \StageModel.title, order: .forward)
    private var stages: [StageModel]

    // Shared with the sACN monitor and the Mac's Spatial Stage window: one relay host for
    // everything, configured in Settings > Network (both relays run on the same VLAN Pi).
    @AppStorage("relayHost") private var relayHost = "10.19.63.10"
    @AppStorage("audioRelayPort") private var relayPort = 1964

    @State private var monitor = TVLiveStageMonitor()
    @State private var selectedStageID: StageIdentifier?
    @State private var errorMessage: String?
    @State private var showError = false

    private var selectedStage: Stage? {
        selectedStageID.flatMap { id in stages.first { $0.id == id } }?.toDTO()
    }

    var body: some View {
        Group {
            if stages.isEmpty {
                ContentUnavailableView {
                    Label("No Stages", systemImage: "square.on.square.dashed")
                } description: {
                    Text(
                        "Create a stage in the console and it will sync here — live monitoring positions each creature's audio channel where it stands on stage."
                    )
                }
            } else {
                Form {
                    Section("Stage") {
                        Picker("Stage", selection: $selectedStageID) {
                            Text("Choose a stage").tag(StageIdentifier?.none)
                            ForEach(stages) { stage in
                                Text(stage.title).tag(Optional(stage.id))
                            }
                        }
                        .disabled(monitor.isRunning)
                    }

                    Section {
                        if monitor.isRunning {
                            Button(role: .destructive) {
                                monitor.stop()
                            } label: {
                                Label("Stop Monitoring", systemImage: "stop.circle.fill")
                            }
                        } else {
                            Button {
                                startMonitoring()
                            } label: {
                                Label("Start Monitoring", systemImage: "person.wave.2")
                            }
                            .disabled(
                                selectedStage == nil
                                    || relayHost.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } footer: {
                        statusFooter
                    }
                }
            }
        }
        .navigationTitle("Live Stage Monitor")
        .alert("Live Monitoring Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onDisappear {
            monitor.stop()
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "Relay: \(relayHost):\(String(relayPort)) — change under Settings › Network Monitors. Run “creature-cli network rtp-listen” there."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(monitor.diagnostics.state.label)
                .font(.headline)
                .foregroundStyle(monitor.isRunning ? .green : .secondary)
            if monitor.isRunning {
                let receiving = monitor.diagnostics.channels.filter { $0.packetsReceived > 0 }
                if !receiving.isEmpty {
                    Text(
                        "Receiving \(receiving.count) channel\(receiving.count == 1 ? "" : "s"): \(receiving.map { String($0.channel) }.joined(separator: ", "))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func startMonitoring() {
        guard let stage = selectedStage else { return }
        do {
            try monitor.start(
                stage: stage,
                host: relayHost.trimmingCharacters(in: .whitespaces),
                port: relayPort
            )
        } catch {
            errorMessage = ServerError.detailedMessage(from: error)
            showError = true
        }
    }
}

/// Owns the renderer + live source lifecycle so the view stays declarative. The Mac equivalent
/// (`SpatialStageViewModel`) also owns stage editing and interface discovery; the TV needs
/// neither, so this stays tiny rather than sharing that class.
@MainActor
@Observable
final class TVLiveStageMonitor {

    private(set) var diagnostics = SpatialStageDiagnostics()
    private(set) var isRunning = false

    @ObservationIgnored private var renderer: SpatialAudioRenderer?
    @ObservationIgnored private var source: SpatialLiveAudioSource?

    enum MonitorError: LocalizedError {
        case noAudioLanes
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .noAudioLanes:
                "This stage has no creatures with audio channels 1–16 to position."
            case .invalidPort:
                "The relay port must be between 1 and 65535."
            }
        }
    }

    func start(stage: Stage, host: String, port: Int) throws {
        stop()

        let channels = Set(stage.placements.map(\.audioChannel)).filter { (1...16).contains($0) }
        guard !channels.isEmpty else {
            throw MonitorError.noAudioLanes
        }
        guard (1...65535).contains(port) else {
            throw MonitorError.invalidPort
        }

        try SpatialAudioSession.configureForMultichannelPlayback()

        let renderer = try SpatialAudioRenderer(channels: channels)
        renderer.update(stage: stage)
        let source = try SpatialLiveAudioSource(
            renderer: renderer,
            channels: channels,
            monitoringDelayMilliseconds: stage.audio.monitoringDelayMilliseconds,
            commonPlayoutDelayMilliseconds: stage.audio.commonPlayoutDelayMilliseconds,
            onDiagnostics: { [weak self] diagnostics in
                Task { @MainActor [weak self] in
                    self?.diagnostics = diagnostics
                }
            }
        )
        try source.start(transport: .relay(host: host, port: UInt16(port)))
        self.renderer = renderer
        self.source = source
        isRunning = true
    }

    func stop() {
        source?.stop()
        source = nil
        renderer = nil
        isRunning = false
        diagnostics = SpatialStageDiagnostics()
    }
}
