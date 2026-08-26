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
    @AppStorage("relayHost") private var relayHost = "10.69.66.1"
    @AppStorage("audioRelayPort") private var relayPort = 1964
    @AppStorage("spatialHeadTrackingEnabled") private var headTrackingEnabled = true
    // Device-level output boost — this room's Denon wants more level than the positional
    // mix provides. Shared with the Spatial Audition screen.
    @AppStorage("monitorBoostDB") private var monitorBoostDB: Double = 0

    @State private var monitor = RelaySpatialStageMonitor()
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

                    Section("Output") {
                        Toggle("Head Tracking", isOn: $headTrackingEnabled)
                            .disabled(monitor.isRunning)
                        TVOutputBoostPicker()
                            .onChange(of: monitorBoostDB) { _, newValue in
                                monitor.setBoost(decibels: Float(newValue))
                            }
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
                port: relayPort,
                headTrackingEnabled: headTrackingEnabled,
                monitorBoostDecibels: Float(monitorBoostDB)
            )
        } catch {
            errorMessage = ServerError.detailedMessage(from: error)
            showError = true
        }
    }
}

/// Output-boost control shared by the TV's listening surfaces. tvOS has no Slider, so this is
/// a stepped picker; the value is post-mix makeup gain in dB, persisted per device.
struct TVOutputBoostPicker: View {

    @AppStorage("monitorBoostDB") private var monitorBoostDB: Double = 0

    var body: some View {
        Picker("Output Boost", selection: $monitorBoostDB) {
            Text("Off").tag(0.0)
            Text("+3 dB").tag(3.0)
            Text("+6 dB").tag(6.0)
            Text("+9 dB").tag(9.0)
            Text("+12 dB").tag(12.0)
        }
    }
}
