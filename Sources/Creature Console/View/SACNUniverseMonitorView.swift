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
    @AppStorage("sacnRemoteHost") private var storedRemoteHost: String = ""
    @AppStorage("sacnRemotePort") private var storedRemotePort: Int = 1963
    @Query(sort: \CreatureModel.name) private var creatures: [CreatureModel]
    @State private var viewModel = SACNUniverseMonitorViewModel()
    @State private var universeString: String = ""
    @State private var remotePortString: String = ""
    @State private var slotOwners: [Int: [SlotOwner]] = [:]
    @State private var creatureLegend: [CreatureLegendEntry] = []
    @State private var creatureSnapshots: [CreatureOverlaySnapshot] = []
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
                    reloadCreatureSnapshots()

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
                    reloadCreatureSnapshots()
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
                TextField("Host", text: $viewModel.remoteHost)
                    .modifier(SACNTextFieldStyle())
                    .frame(width: 180)
                    .focused($focusedField, equals: .remoteHost)
                    #if os(tvOS)
                        .prefersDefaultFocus(viewModel.source == .remote, in: headerFocusScope)
                    #endif
                TextField("Port", text: $remotePortString)
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

    private var statusLine: some View {
        HStack(spacing: 12) {
            Label(statusText, systemImage: statusSymbol)
                .foregroundStyle(statusTint)
            if let lastPacketDate = viewModel.lastPacketDate {
                Text("Last packet \(lastPacketDate, style: .relative)")
                    .foregroundStyle(.secondary)
            }
            if let sequence = viewModel.lastSequence {
                Text("Seq \(sequence)")
                    .foregroundStyle(.secondary)
            }
            Text("Packets \(viewModel.packetCount)")
                .foregroundStyle(.secondary)
        }
    }

    private var grid: some View {
        SACNUniverseGridView(
            slots: viewModel.slots,
            slotOwners: slotOwners
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Creature Overlay")
                .font(.headline)
            if creatureLegend.isEmpty {
                Text("No creatures loaded.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 16)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(creatureLegend) { entry in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(entry.color.opacity(0.7))
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(entry.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
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

    private func rebuildCreatureOverlay() {
        var slotOwners: [Int: [SlotOwner]] = [:]
        var legend: [CreatureLegendEntry] = []
        let creatureColors = creatureColorMap(for: creatureSnapshots)

        for creature in creatureSnapshots {
            let color = creatureColors[creature.id] ?? .gray
            var slotIndices: [Int] = []

            for input in creature.inputs {
                let slotIndex = creature.channelOffset + Int(input.slot)
                guard (1...512).contains(slotIndex) else {
                    continue
                }
                slotIndices.append(slotIndex)
                slotOwners[slotIndex, default: []].append(
                    SlotOwner(
                        id: "\(creature.id):input:\(input.name):\(slotIndex)",
                        creatureID: creature.id,
                        creatureName: creature.name,
                        label: input.name,
                        color: color
                    )
                )
            }

            if creature.mouthSlot > 0 {
                let mouthSlot = creature.channelOffset + creature.mouthSlot
                if (1...512).contains(mouthSlot) {
                    slotIndices.append(mouthSlot)
                    slotOwners[mouthSlot, default: []].append(
                        SlotOwner(
                            id: "\(creature.id):mouth:\(mouthSlot)",
                            creatureID: creature.id,
                            creatureName: creature.name,
                            label: "Mouth",
                            color: color
                        )
                    )
                }
            }

            let range = slotIndices.isEmpty ? nil : (slotIndices.min()!...slotIndices.max()!)
            legend.append(
                CreatureLegendEntry(
                    id: creature.id,
                    name: creature.name,
                    color: color,
                    slotRange: range,
                    slotCount: slotIndices.count
                )
            )
        }

        self.slotOwners = slotOwners
        creatureLegend = legend.sorted { $0.name < $1.name }
    }

    private func creatureColorMap(for creatures: [CreatureOverlaySnapshot]) -> [String: Color] {
        let goldenRatio = 0.618033988749895
        let saturation = 0.7
        let brightness = 0.9
        let orderedCreatures = creatures.sorted { $0.name < $1.name }
        var currentHue = 0.0
        var map: [String: Color] = [:]

        for creature in orderedCreatures {
            currentHue = fmod(currentHue + goldenRatio, 1.0)
            map[creature.id] = Color(
                hue: currentHue,
                saturation: saturation,
                brightness: brightness
            )
        }

        return map
    }

    private func reloadCreatureSnapshots() {
        Task {
            let container = await SwiftDataStore.shared.container()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<CreatureModel>(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            do {
                let models = try context.fetch(descriptor)
                let snapshots = models.map { creature in
                    CreatureOverlaySnapshot(
                        id: creature.id,
                        name: creature.name,
                        channelOffset: creature.channelOffset,
                        mouthSlot: creature.mouthSlot,
                        inputs: creature.inputs
                            .sorted { $0.slot < $1.slot }
                            .map { input in
                                CreatureInputSnapshot(
                                    name: input.name,
                                    slot: Int(input.slot),
                                    width: Int(input.width)
                                )
                            }
                    )
                }
                await MainActor.run {
                    creatureSnapshots = snapshots
                    rebuildCreatureOverlay()
                }
            } catch {
                await MainActor.run {
                    creatureSnapshots = []
                    slotOwners = [:]
                    creatureLegend = []
                }
            }
        }
    }
}

private struct CreatureOverlaySnapshot: Identifiable {
    let id: String
    let name: String
    let channelOffset: Int
    let mouthSlot: Int
    let inputs: [CreatureInputSnapshot]
}

private struct CreatureInputSnapshot {
    let name: String
    let slot: Int
    let width: Int
}

struct SlotOwner: Identifiable {
    let id: String
    let creatureID: String
    let creatureName: String
    let label: String
    let color: Color
}

private struct CreatureLegendEntry: Identifiable {
    let id: String
    let name: String
    let color: Color
    let slotRange: ClosedRange<Int>?
    let slotCount: Int

    var detail: String {
        if let slotRange {
            return "Slots \(slotRange.lowerBound)–\(slotRange.upperBound) · \(slotCount) inputs"
        }
        return "No slots mapped"
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
