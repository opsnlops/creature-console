import Common
import SwiftData
import SwiftUI

enum SACNMonitorLayoutStyle {
    case standard
    case fullScreen
}

struct SACNUniverseMonitorView: View {
    let layoutStyle: SACNMonitorLayoutStyle

    init(layoutStyle: SACNMonitorLayoutStyle = .standard) {
        self.layoutStyle = layoutStyle
    }

    private enum FocusField: Hashable {
        case remoteHost
        case remotePort
        case universe
    }

    @AppStorage("activeUniverse") private var activeUniverse: Int = 1
    @AppStorage("sacnMonitorSource") private var storedSource: String = defaultSourceRawValue
    @AppStorage("relayHost") private var storedRemoteHost: String = "10.19.63.10"
    @AppStorage("sacnRelayPort") private var storedRemotePort: Int = 1963
    @Query(sort: \CreatureModel.name) private var creatures: [CreatureModel]
    @Query(sort: \DmxFixtureModel.name) private var fixtures: [DmxFixtureModel]
    @State private var viewModel = SACNUniverseMonitorViewModel()
    @State private var universeString: String = ""
    @State private var remotePortString: String = ""
    @State private var slotOwners: [Int: [SACNSlotOwner]] = [:]
    @State private var creatureLegend: [SACNOverlayLegendEntry] = []
    @State private var fixtureLegend: [SACNOverlayLegendEntry] = []
    @State private var overlayCreatures: [Common.Creature] = []
    @State private var overlayFixtures: [DmxFixture] = []
    @FocusState private var focusedField: FocusField?
    @Namespace private var headerFocusScope
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .onAppear {
                Task { @MainActor in
                    universeString = String(activeUniverse)
                    remotePortString = String(storedRemotePort)
                    viewModel.setUniverse(activeUniverse)
                    viewModel.remoteHost = storedRemoteHost
                    viewModel.remotePort = storedRemotePort
                    viewModel.source = MonitorSource(rawValue: storedSource) ?? .local
                    reloadOverlaySources()

                    #if os(tvOS)
                        if viewModel.source == .remote {
                            focusedField = .remoteHost
                        } else {
                            focusedField = .universe
                        }
                        if !viewModel.isRunning, canConnect {
                            viewModel.connect()
                        }
                    #endif
                }
            }
            .onChange(of: activeUniverse) { _, newValue in
                Task { @MainActor in
                    universeString = String(newValue)
                    viewModel.setUniverse(newValue)
                }
            }
            .onChange(of: viewModel.source) { _, newValue in
                Task { @MainActor in
                    storedSource = newValue.rawValue
                }
            }
            .onChange(of: viewModel.remoteHost) { _, newValue in
                Task { @MainActor in
                    storedRemoteHost = newValue
                }
            }
            .onChange(of: viewModel.remotePort) { _, newValue in
                Task { @MainActor in
                    storedRemotePort = newValue
                }
            }
            .onChange(of: creatures) { _, _ in
                Task { @MainActor in
                    reloadOverlaySources()
                }
            }
            .onChange(of: fixtures) { _, _ in
                Task { @MainActor in
                    reloadOverlaySources()
                }
            }
            .onChange(of: viewModel.universe) { _, _ in
                // Fixtures are patched to a specific universe, so the overlay changes
                // whenever we point the monitor somewhere else.
                Task { @MainActor in
                    rebuildOverlay()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch layoutStyle {
        case .standard:
            standardContent
        case .fullScreen:
            fullScreenContent
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            grid
            legend
                .padding(.horizontal, legendHorizontalPadding)
        }
        .padding(16)
    }

    private var fullScreenContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(tvOS)
                VStack(spacing: 6) {
                    Text("Universe \(viewModel.universe)")
                        .font(.title3.weight(.semibold))
                    statusLine
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.horizontal, 20)
            #else
                header
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            #endif

            grid
                .layoutPriority(1)

            legend
        }
        .padding(16)
    }

    private var legendBottomPadding: CGFloat {
        #if os(tvOS)
            return 56
        #else
            return 4
        #endif
    }

    private var legendHorizontalPadding: CGFloat {
        #if os(tvOS)
            return 16
        #else
            return 0
        #endif
    }

    private static var defaultSourceRawValue: String {
        #if os(macOS)
            return MonitorSource.local.rawValue
        #else
            return MonitorSource.remote.rawValue
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                #if !os(tvOS)
                    sourcePicker
                #endif
                if viewModel.source == .local {
                    interfacePicker
                } else {
                    #if os(tvOS)
                        remoteStatus
                    #else
                        remoteSelector
                    #endif
                }
                universeSelector
                headerActions
            }
            #if !os(tvOS)
                statusLine
            #endif
        }
        #if os(tvOS)
            .focusSection()
            .focusScope(headerFocusScope)
        #endif
    }

    private var interfacePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Interface")
                .font(.headline)
            Picker(
                "Interface",
                selection: Binding(
                    get: { viewModel.selectedInterfaceID ?? "" },
                    set: { viewModel.setSelectedInterface(id: $0.isEmpty ? nil : $0) }
                )
            ) {
                if viewModel.interfaces.isEmpty {
                    Text("No interfaces found").tag("")
                } else {
                    ForEach(viewModel.interfaces) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }
            }
            .frame(maxWidth: 360)
            .pickerStyle(.menu)
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source")
                .font(.headline)
            Picker("Source", selection: $viewModel.source) {
                ForEach(MonitorSource.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            .frame(width: 180)
            .pickerStyle(.segmented)
        }
    }

    private var remoteSelector: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Remote Listener")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("Relay Host", text: $viewModel.remoteHost)
                    .modifier(SACNTextFieldStyle())
                    .frame(width: 180)
                    .focused($focusedField, equals: .remoteHost)
                    #if os(tvOS)
                        .prefersDefaultFocus(viewModel.source == .remote, in: headerFocusScope)
                    #endif
                TextField("Relay Port", text: $remotePortString)
                    .modifier(SACNTextFieldStyle())
                    .frame(width: 70)
                    .focused($focusedField, equals: .remotePort)
                    .onChange(of: remotePortString) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            remotePortString = filtered
                        }
                        if let value = Int(filtered) {
                            let clamped = min(max(value, 1), 65_535)
                            if clamped != value {
                                remotePortString = String(clamped)
                            }
                            viewModel.remotePort = clamped
                        }
                    }
            }
        }
    }

    private var remoteStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Remote Listener")
                .font(.headline)
            Text(viewModel.remoteHost.isEmpty ? "Not set" : viewModel.remoteHost)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var universeSelector: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Universe")
                .font(.headline)
            TextField("1–63999", text: $universeString)
                .modifier(SACNTextFieldStyle())
                .frame(width: 96)
                .focused($focusedField, equals: .universe)
                #if os(tvOS)
                    .prefersDefaultFocus(viewModel.source == .local, in: headerFocusScope)
                #endif
                .onChange(of: universeString) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        universeString = filtered
                    }
                    if let value = Int(filtered) {
                        let clamped = min(max(value, 1), 63999)
                        if clamped != value {
                            universeString = String(clamped)
                        }
                        viewModel.setUniverse(clamped)
                    }
                }
        }
    }

    private var headerActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(" ")
                .font(.headline)
                .hidden()
            HStack(spacing: 12) {
                Button(viewModel.isRunning ? "Disconnect" : "Connect") {
                    if viewModel.isRunning {
                        viewModel.disconnect()
                    } else {
                        viewModel.connect()
                    }
                }
                .disabled(!canConnect)
                Button("Use Active Universe") {
                    universeString = String(activeUniverse)
                    viewModel.setUniverse(activeUniverse)
                }
            }
        }
    }

    private var canConnect: Bool {
        switch viewModel.source {
        case .local:
            return viewModel.selectedInterfaceID != nil
        case .remote:
            let host = viewModel.remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
            return !host.isEmpty && (1...65_535).contains(viewModel.remotePort)
        }
    }

    // The status line and grid live in child views so only they track the receiver's
    // high-rate properties — read in this struct's body, every flush would re-render the
    // whole monitor, header pickers included (#76).
    private var statusLine: some View {
        SACNMonitorStatusLine(viewModel: viewModel)
    }

    private var grid: some View {
        SACNMonitorGrid(viewModel: viewModel, slotOwners: slotOwners)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 16) {
            legendSection(
                title: "Creatures",
                systemImage: "pawprint.fill",
                entries: creatureLegend,
                emptyMessage: "No creatures loaded."
            )
            legendSection(
                title: "Fixtures",
                systemImage: "lightbulb.fill",
                entries: fixtureLegend,
                emptyMessage: "No fixtures patched to universe \(viewModel.universe)."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func legendSection(
        title: String,
        systemImage: String,
        entries: [SACNOverlayLegendEntry],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            if entries.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: 16)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(entries) { entry in
                        legendRow(entry)
                    }
                }
            }
        }
    }

    private func legendRow(_ entry: SACNOverlayLegendEntry) -> some View {
        HStack(spacing: 8) {
            // Same shape language as the grid markers: round for creatures, square for fixtures.
            RoundedRectangle(cornerRadius: 14 * entry.kind.markerCornerFraction)
                .fill(entry.color.opacity(0.7))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                Text(legendDetail(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legendDetail(for entry: SACNOverlayLegendEntry) -> String {
        var parts: [String] = []

        if let fixtureType = entry.fixtureType {
            parts.append(fixtureType.displayName)
        }

        if entry.kind == .fixture, entry.assignedUniverse == nil {
            parts.append("No universe assigned")
            return parts.joined(separator: " · ")
        }

        if let slotRange = entry.slotRange {
            parts.append("Slots \(slotRange.lowerBound)–\(slotRange.upperBound)")
            parts.append(
                "\(entry.slotCount) \(entry.kind == .fixture ? "channels" : "inputs")"
            )
        } else {
            parts.append("No slots mapped")
        }

        return parts.joined(separator: " · ")
    }

    /// Recompute who owns which slot for the universe we're currently watching. Cheap enough
    /// to redo on a universe change — it's a walk over the cached creatures and fixtures.
    private func rebuildOverlay() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: overlayCreatures,
            fixtures: overlayFixtures,
            universe: UInt32(clamping: viewModel.universe)
        )
        slotOwners = overlay.slotOwners
        creatureLegend = overlay.creatures
        fixtureLegend = overlay.fixtures
    }

    /// Pull the creatures and fixtures out of SwiftData on a background context and hand the
    /// value-type DTOs back to the main actor.
    private func reloadOverlaySources() {
        Task {
            let container = await SwiftDataStore.shared.container()
            let context = ModelContext(container)
            let creatureDescriptor = FetchDescriptor<CreatureModel>(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            let fixtureDescriptor = FetchDescriptor<DmxFixtureModel>(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            do {
                let creatures = try context.fetch(creatureDescriptor).map { $0.toDTO() }
                let fixtures = try context.fetch(fixtureDescriptor).map { $0.toDTO() }
                await MainActor.run {
                    overlayCreatures = creatures
                    overlayFixtures = fixtures
                    rebuildOverlay()
                }
            } catch {
                await MainActor.run {
                    overlayCreatures = []
                    overlayFixtures = []
                    rebuildOverlay()
                }
            }
        }
    }
}

private struct SACNMonitorStatusLine: View {
    var viewModel: SACNUniverseMonitorViewModel

    var body: some View {
        HStack(spacing: 12) {
            Label(statusText, systemImage: statusSymbol)
                .foregroundStyle(statusTint)
            if let lastPacketDate = viewModel.lastPacketDate {
                Text("Last packet \(lastPacketDate, style: .relative)")
                    .foregroundStyle(.secondary)
            }
            if let sequence = viewModel.lastSequence {
                Text("Seq \(sequence)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text("Packets \(viewModel.packetCount)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch viewModel.status {
        case .idle:
            return "Idle"
        case .waitingForInterface:
            return "Select a network interface"
        case .waitingForRemoteHost:
            return "Enter a remote host"
        case .connecting:
            return "Connecting…"
        case .waitingForPackets:
            return "Listening (waiting for packets)"
        case .listening:
            return "Listening"
        case .failed(let message):
            return "Error: \(message)"
        }
    }

    private var statusSymbol: String {
        switch viewModel.status {
        case .failed:
            return "exclamationmark.triangle.fill"
        case .waitingForInterface:
            return "network.slash"
        case .waitingForRemoteHost:
            return "link.badge.plus"
        case .connecting:
            return "link"
        case .waitingForPackets:
            return "dot.radiowaves.left.and.right"
        case .listening:
            return "dot.radiowaves.left.and.right"
        case .idle:
            return "pause.circle"
        }
    }

    private var statusTint: Color {
        switch viewModel.status {
        case .failed:
            return .red
        case .waitingForInterface:
            return .orange
        case .waitingForRemoteHost:
            return .orange
        case .connecting:
            return .blue
        case .waitingForPackets:
            return .blue
        case .listening:
            return .green
        case .idle:
            return .secondary
        }
    }
}

private struct SACNMonitorGrid: View {
    var viewModel: SACNUniverseMonitorViewModel
    let slotOwners: [Int: [SACNSlotOwner]]

    var body: some View {
        SACNUniverseGridView(
            slots: viewModel.slots,
            slotOwners: slotOwners
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }
}

private struct SACNTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
            content
                .textFieldStyle(.plain)
                .focusable(true)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.2))
                )
        #else
            content
                .textFieldStyle(.roundedBorder)
        #endif
    }
}
