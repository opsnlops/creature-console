import Common
import Network
import SwiftData
import SwiftUI

#if os(iOS) || os(tvOS)
    import UIKit
#endif

enum MonitorSource: String, CaseIterable, Identifiable {
    case local
    case remote

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local:
            return "Local"
        case .remote:
            return "Remote"
        }
    }
}

@MainActor
final class SACNUniverseMonitorViewModel: ObservableObject {
    @Published var interfaces: [SACNInterface] = []
    @Published var selectedInterfaceID: String?
    @Published var universe: Int = 1
    @Published var isRunning: Bool = false
    @Published var source: MonitorSource = .local {
        didSet {
            if oldValue != source, isRunning {
                restartReceiver()
            }
        }
    }
    @Published var remoteHost: String = "" {
        didSet {
            if oldValue != remoteHost, source == .remote, isRunning {
                restartReceiver()
            }
        }
    }
    @Published var remotePort: Int = 1963 {
        didSet {
            if oldValue != remotePort, source == .remote, isRunning {
                restartReceiver()
            }
        }
    }
    @Published var slots: [UInt8] = Array(repeating: 0, count: 512)
    @Published var status: MonitorStatus = .idle
    @Published var lastPacketDate: Date?
    @Published var lastSequence: UInt8?
    @Published var packetCount: Int = 0

    enum MonitorStatus: Equatable {
        case idle
        case waitingForInterface
        case waitingForRemoteHost
        case connecting
        case waitingForPackets
        case listening
        case failed(String)
    }

    private let receiver = SACNReceiver()
    private let remoteReceiver = SACNRemoteReceiver()
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "io.opsnlops.CreatureConsole.SACNPathMonitor")
    private let framePublishInterval: UInt64 = 20_000_000
    private var pendingSlots: [UInt8] = Array(repeating: 0, count: 512)
    private var pendingSequence: UInt8?
    private var pendingPacketCount: Int = 0
    private var pendingLastPacketDate: Date?
    private var isFlushScheduled = false

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let options = SACNInterfaceCatalog.interfaceOptions(from: path)
            DispatchQueue.main.async {
                self?.updateInterfaces(options)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    deinit {
        pathMonitor.cancel()
        receiver.stop()
        remoteReceiver.stop()
    }

    func updateInterfaces(_ newInterfaces: [SACNInterface]) {
        interfaces = newInterfaces
        if let selectedInterfaceID,
            newInterfaces.contains(where: { $0.id == selectedInterfaceID })
        {
            return
        }
        selectedInterfaceID = newInterfaces.first?.id
        if isRunning {
            restartReceiver()
        }
    }

    func setUniverse(_ newUniverse: Int) {
        let clamped = min(max(newUniverse, 1), 63999)
        guard universe != clamped else {
            return
        }
        universe = clamped
        if isRunning {
            restartReceiver()
        }
    }

    func setSelectedInterface(id: String?) {
        guard selectedInterfaceID != id else {
            return
        }
        selectedInterfaceID = id
        if isRunning {
            restartReceiver()
        }
    }

    func connect() {
        guard !isRunning else {
            return
        }
        isRunning = true
        restartReceiver()
    }

    func disconnect() {
        guard isRunning else {
            return
        }
        isRunning = false
        receiver.stop()
        remoteReceiver.stop()
        status = .idle
    }

    func restartReceiver() {
        guard isRunning else {
            status = .idle
            return
        }
        receiver.stop()
        remoteReceiver.stop()
        slots = Array(repeating: 0, count: 512)
        lastPacketDate = nil
        lastSequence = nil
        packetCount = 0
        pendingSlots = Array(repeating: 0, count: 512)
        pendingSequence = nil
        pendingPacketCount = 0
        pendingLastPacketDate = nil
        isFlushScheduled = false

        if source == .local {
            guard let interface = selectedInterface else {
                status = .waitingForInterface
                return
            }

            status = .waitingForPackets
            let universeValue = UInt16(min(max(universe, 1), 63999))

            do {
                try receiver.start(
                    universe: universeValue,
                    interface: interface.nwInterface,
                    onPacket: { [weak self] packet in
                        guard packet.frame.universe == universeValue else {
                            return
                        }
                        Task { @MainActor in
                            self?.enqueueFrame(packet.frame)
                        }
                    },
                    onState: { [weak self] state in
                        Task { @MainActor in
                            self?.handleStateUpdate(state)
                        }
                    }
                )
            } catch {
                status = .failed(error.localizedDescription)
            }
            return
        }

        guard !remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = .waitingForRemoteHost
            return
        }

        guard remotePort > 0, remotePort <= 65535 else {
            status = .failed("Invalid port")
            return
        }

        status = .connecting
        let universeValue = UInt16(min(max(universe, 1), 63999))
        let hello = SACNRemoteHello(
            viewerName: viewerName,
            viewerVersion: appVersion,
            universe: universeValue
        )
        remoteReceiver.start(
            host: remoteHost,
            port: UInt16(remotePort),
            hello: hello,
            onFrame: { [weak self] frame in
                guard frame.universe == universeValue else {
                    return
                }
                Task { @MainActor in
                    self?.enqueueFrame(frame)
                }
            },
            onState: { [weak self] state in
                Task { @MainActor in
                    self?.handleRemoteStateUpdate(state)
                }
            }
        )
    }

    private func handleStateUpdate(_ state: NWConnectionGroup.State) {
        switch state {
        case .failed(let error):
            status = .failed(error.localizedDescription)
        case .ready:
            if status == .waitingForInterface {
                status = .waitingForPackets
            }
        default:
            break
        }
    }

    private func handleRemoteStateUpdate(_ state: NWConnection.State) {
        switch state {
        case .ready:
            if status == .connecting {
                status = .waitingForPackets
            }
        case .failed(let error):
            status = .failed(error.localizedDescription)
        case .cancelled:
            status = .idle
        default:
            break
        }
    }

    private var selectedInterface: SACNInterface? {
        interfaces.first { $0.id == selectedInterfaceID }
    }

    private func enqueueFrame(_ frame: SACNFrame) {
        pendingSlots = frame.slots
        pendingSequence = frame.sequence
        pendingLastPacketDate = Date()
        pendingPacketCount += 1
        if !isFlushScheduled {
            isFlushScheduled = true
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.framePublishInterval)
                await MainActor.run {
                    self.flushPendingFrames()
                }
            }
        }
    }

    private func flushPendingFrames() {
        slots = pendingSlots
        lastSequence = pendingSequence
        if let pendingLastPacketDate {
            lastPacketDate = pendingLastPacketDate
        }
        if pendingPacketCount > 0 {
            packetCount += pendingPacketCount
        }
        pendingPacketCount = 0
        pendingLastPacketDate = nil
        isFlushScheduled = false
        if isRunning, status != .listening {
            status = .listening
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case (let version?, let build?):
            return "\(version) (\(build))"
        case (let version?, nil):
            return version
        case (nil, let build?):
            return build
        default:
            return "Unknown"
        }
    }

    private var viewerName: String {
        #if os(iOS) || os(tvOS)
            return UIDevice.current.name
        #else
            return Host.current().localizedName ?? "Creature Console"
        #endif
    }
}

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
    @StateObject private var viewModel = SACNUniverseMonitorViewModel()
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
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

private struct SlotOwner: Identifiable {
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

final class SACNRemoteReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.opsnlops.CreatureConsole.SACNRemoteReceiver")
    private var connection: NWConnection?
    private var buffer = Data()

    func start(
        host: String,
        port: UInt16,
        hello: SACNRemoteHello,
        onFrame: @escaping @Sendable (SACNFrame) -> Void,
        onState: @escaping @Sendable (NWConnection.State) -> Void
    ) {
        stop()

        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 9011)
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            onState(state)
            if case .ready = state {
                self?.sendHello(hello, over: connection)
                self?.receiveLoop(on: connection, onFrame: onFrame)
            }
        }
        connection.start(queue: queue)
        self.connection = connection
    }

    func stop() {
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: true)
    }

    private func sendHello(_ hello: SACNRemoteHello, over connection: NWConnection) {
        do {
            let data = try JSONEncoder().encode(hello)
            var message = Data()
            message.append(data)
            message.append(0x0A)
            connection.send(content: message, completion: .contentProcessed { _ in })
        } catch {
            return
        }
    }

    private func receiveLoop(
        on connection: NWConnection, onFrame: @escaping @Sendable (SACNFrame) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self] data, _, isComplete, error in
            if let data {
                self?.buffer.append(data)
                self?.processBuffer(onFrame: onFrame)
            }

            if error == nil, !isComplete {
                self?.receiveLoop(on: connection, onFrame: onFrame)
            }
        }
    }

    private func processBuffer(onFrame: @escaping @Sendable (SACNFrame) -> Void) {
        while buffer.count >= SACNRemoteStream.lengthPrefixSize {
            let length = Int(buffer[0]) << 8 | Int(buffer[1])
            guard length > 0, length <= SACNRemoteStream.maxPacketSize else {
                buffer.removeAll(keepingCapacity: true)
                connection?.cancel()
                return
            }
            let packetLength = SACNRemoteStream.lengthPrefixSize + length
            guard buffer.count >= packetLength else {
                break
            }

            let payload = buffer.subdata(in: 2..<packetLength)
            buffer.removeSubrange(0..<packetLength)
            if let frame = SACNParser.parse(data: payload) {
                onFrame(frame)
            }
        }
    }
}

private struct SACNUniverseGridView: View {
    let slots: [UInt8]
    let slotOwners: [Int: [SlotOwner]]
    private let columnsCount = 32
    private let rowsCount = 16
    private let gridPadding: CGFloat = 32

    var body: some View {
        #if os(iOS) || os(tvOS)
            SACNUniverseCanvasGridView(
                slots: slots,
                slotOwners: slotOwners,
                columnsCount: columnsCount,
                rowsCount: rowsCount,
                gridPadding: gridPadding
            )
        #else
            GeometryReader { geometry in
                let spacing: CGFloat = 2
                let availableWidth = geometry.size.width - spacing * CGFloat(columnsCount - 1)
                let availableHeight = geometry.size.height - spacing * CGFloat(rowsCount - 1)
                let cellWidth = max(8, min(40, availableWidth / CGFloat(columnsCount)))
                let cellHeight = max(6, min(28, availableHeight / CGFloat(rowsCount)))
                let cellSize = CGSize(width: cellWidth, height: cellHeight)
                let backgroundColor = gridBackgroundColor

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(cellSize.width), spacing: spacing),
                            count: columnsCount
                        ),
                        spacing: spacing
                    ) {
                        ForEach(0..<512, id: \.self) { index in
                            let slotIndex = index + 1
                            let rowIndex = index / columnsCount
                            let columnIndex = index % columnsCount
                            SACNSlotCellView(
                                slotIndex: slotIndex,
                                rowIndex: rowIndex,
                                columnIndex: columnIndex,
                                rowsCount: rowsCount,
                                columnsCount: columnsCount,
                                value: slots[safe: index] ?? 0,
                                owners: slotOwners[slotIndex, default: []],
                                size: cellSize
                            )
                        }
                    }
                }
            }
        #endif
    }

    private var gridBackgroundColor: Color {
        #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
        #elseif os(tvOS)
            return Color(white: 0.16)
        #else
            return Color(.secondarySystemBackground)
        #endif
    }
}

#if os(iOS) || os(tvOS)
    private struct SACNUniverseCanvasGridView: View {
        let slots: [UInt8]
        let slotOwners: [Int: [SlotOwner]]
        let columnsCount: Int
        let rowsCount: Int
        let gridPadding: CGFloat
        @Environment(\.colorScheme) private var colorScheme
        @State private var gridImage: Image?
        @State private var cachedSize: CGSize = .zero

        var body: some View {
            GeometryReader { geometry in
                let layout = GridLayout(
                    size: CGSize(
                        width: max(0, geometry.size.width - gridPadding * 2),
                        height: max(0, geometry.size.height - gridPadding * 2)
                    ),
                    columnsCount: columnsCount,
                    rowsCount: rowsCount
                )
                let gridBackground = gridBackgroundColor

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(gridBackground)
                    if let gridImage {
                        gridImage
                            .resizable()
                            .frame(width: layout.totalSize.width, height: layout.totalSize.height)
                            .position(
                                x: gridPadding + layout.origin.x + layout.totalSize.width / 2,
                                y: gridPadding + layout.origin.y + layout.totalSize.height / 2
                            )
                    }
                    Canvas { context, _ in
                        for index in 0..<512 {
                            let slotIndex = index + 1
                            let rowIndex = index / columnsCount
                            let columnIndex = index % columnsCount
                            let x =
                                gridPadding + layout.origin.x
                                + CGFloat(columnIndex) * (layout.cellSize.width + layout.spacing)
                            let y =
                                gridPadding + layout.origin.y
                                + CGFloat(rowIndex) * (layout.cellSize.height + layout.spacing)
                            let rect = CGRect(
                                x: x,
                                y: y,
                                width: layout.cellSize.width,
                                height: layout.cellSize.height
                            )

                            context.fill(
                                Path(rect),
                                with: .color(slotFill(for: slots[safe: index] ?? 0))
                            )

                            if let owner = slotOwners[slotIndex]?.first {
                                context.fill(Path(rect), with: .color(owner.color.opacity(0.28)))
                                let outlineWidth =
                                    max(1, min(layout.cellSize.width, layout.cellSize.height) / 12)
                                context.stroke(
                                    Path(rect),
                                    with: .color(owner.color.opacity(0.65)),
                                    lineWidth: outlineWidth
                                )
                            }

                            if let owners = slotOwners[slotIndex] {
                                let dotOwners = owners.prefix(3)
                                if !dotOwners.isEmpty {
                                    let dotSize = layout.minDimension / 3.5
                                    let dotSpacing: CGFloat = 1
                                    let totalDotsWidth =
                                        CGFloat(dotOwners.count) * dotSize
                                        + CGFloat(max(0, dotOwners.count - 1)) * dotSpacing
                                    var dotX = rect.maxX - 1 - totalDotsWidth
                                    let dotY = rect.maxY - 1 - dotSize
                                    for owner in dotOwners {
                                        let dotRect = CGRect(
                                            x: dotX,
                                            y: dotY,
                                            width: dotSize,
                                            height: dotSize
                                        )
                                        context.fill(
                                            Path(ellipseIn: dotRect), with: .color(owner.color))
                                        dotX += dotSize + dotSpacing
                                    }
                                }
                            }

                            if (slotIndex - 1) % 16 == 0 {
                                let fontSize = max(8, min(12, layout.minDimension * 0.35))
                                let label = Text("\(slotIndex)")
                                    .font(
                                        .system(
                                            size: fontSize, weight: .semibold, design: .monospaced)
                                    )
                                    .foregroundStyle(.white.opacity(0.85))
                                let textPoint = CGPoint(
                                    x: rect.minX + 2,
                                    y: rect.minY + 1
                                )
                                context.draw(label, at: textPoint, anchor: .topLeading)
                            }
                        }
                    }
                }
                .onAppear {
                    updateGridImage(for: geometry.size)
                }
                .onChange(of: geometry.size) { _, newValue in
                    updateGridImage(for: newValue)
                }
                .onChange(of: colorScheme) { _, _ in
                    updateGridImage(for: geometry.size)
                }
            }
        }

        private func slotFill(for value: UInt8) -> Color {
            let normalized = Double(value) / 255.0
            if colorScheme == .dark {
                return Color(white: 0.005 + (normalized * 0.88))
            }
            return Color(white: 1.0 - normalized)
        }

        private var gridBackgroundColor: Color {
            #if os(macOS)
                return Color(nsColor: .controlBackgroundColor)
            #elseif os(tvOS)
                return Color(white: 0.16)
            #else
                return Color(.secondarySystemBackground)
            #endif
        }

        private func updateGridImage(for size: CGSize) {
            guard size != .zero else {
                return
            }
            if size == cachedSize, gridImage != nil {
                return
            }
            cachedSize = size
            let layout = GridLayout(
                size: CGSize(
                    width: max(0, size.width - gridPadding * 2),
                    height: max(0, size.height - gridPadding * 2)
                ),
                columnsCount: columnsCount,
                rowsCount: rowsCount
            )
            let image = renderGridImage(layout: layout)
            gridImage = Image(uiImage: image)
        }

        private func renderGridImage(layout: GridLayout) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: layout.totalSize)
            return renderer.image { context in
                let cgContext = context.cgContext
                let lineColor =
                    (colorScheme == .dark)
                    ? UIColor(white: 1.0, alpha: 0.18)
                    : UIColor(white: 0.0, alpha: 0.2)
                cgContext.setStrokeColor(lineColor.cgColor)
                cgContext.setLineWidth(0.8)

                for index in 0..<512 {
                    let slotIndex = index + 1
                    let rowIndex = index / columnsCount
                    let columnIndex = index % columnsCount
                    let x = CGFloat(columnIndex) * (layout.cellSize.width + layout.spacing)
                    let y = CGFloat(rowIndex) * (layout.cellSize.height + layout.spacing)
                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: layout.cellSize.width,
                        height: layout.cellSize.height
                    )
                    let path = gridLinePath(
                        rect: rect,
                        rowIndex: rowIndex,
                        columnIndex: columnIndex,
                        rowsCount: rowsCount,
                        columnsCount: columnsCount
                    )
                    cgContext.addPath(path.cgPath)

                    if (slotIndex - 1) % 16 == 0 {
                        let fontSize = max(6, min(10, layout.minDimension * 0.35))
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                            .foregroundColor: UIColor.label.withAlphaComponent(0.7),
                        ]
                        let label = "\(slotIndex)" as NSString
                        label.draw(
                            at: CGPoint(x: rect.minX + 1, y: rect.minY + 1),
                            withAttributes: attributes
                        )
                    }
                }
                cgContext.strokePath()
            }
        }

        private func gridLinePath(
            rect: CGRect,
            rowIndex: Int,
            columnIndex: Int,
            rowsCount: Int,
            columnsCount: Int
        ) -> Path {
            Path { path in
                path.move(to: rect.origin)
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.move(to: rect.origin)
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

                if columnIndex == columnsCount - 1 {
                    path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                }
                if rowIndex == rowsCount - 1 {
                    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                }
            }
        }
    }

    private struct GridLayout {
        let spacing: CGFloat = 2
        let cellSize: CGSize
        let origin: CGPoint
        let totalSize: CGSize
        let minDimension: CGFloat

        init(size: CGSize, columnsCount: Int, rowsCount: Int) {
            let availableWidth = size.width - spacing * CGFloat(columnsCount - 1)
            let availableHeight = size.height - spacing * CGFloat(rowsCount - 1)
            let cellWidth = max(8, availableWidth / CGFloat(columnsCount))
            let cellHeight = max(6, availableHeight / CGFloat(rowsCount))
            cellSize = CGSize(width: cellWidth, height: cellHeight)
            totalSize = CGSize(
                width: cellWidth * CGFloat(columnsCount) + spacing * CGFloat(columnsCount - 1),
                height: cellHeight * CGFloat(rowsCount) + spacing * CGFloat(rowsCount - 1)
            )
            origin = CGPoint(
                x: max(0, (size.width - totalSize.width) / 2),
                y: max(0, (size.height - totalSize.height) / 2)
            )
            minDimension = min(cellWidth, cellHeight)
        }
    }
#endif

private struct SACNSlotCellView: View {
    let slotIndex: Int
    let rowIndex: Int
    let columnIndex: Int
    let rowsCount: Int
    let columnsCount: Int
    let value: UInt8
    let owners: [SlotOwner]
    let size: CGSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shade = slotShade
        Rectangle()
            .fill(Color(white: shade))
            .frame(width: size.width, height: size.height)
            .overlay(overlayTint)
            .overlay(ownerOutline)
            .overlay(slotLabel)
            .overlay(ownerDots, alignment: .bottomTrailing)
            .overlay(gridLines)
            .accessibilityLabel("Slot \(slotIndex) value \(value)")
            .help(ownersHelpText)
    }

    private var overlayTint: some View {
        Group {
            if let owner = owners.first {
                Rectangle()
                    .fill(owner.color.opacity(0.28))
            }
        }
    }

    private var ownerOutline: some View {
        Group {
            if let owner = owners.first {
                Rectangle()
                    .stroke(owner.color.opacity(0.65), lineWidth: max(1, minDimension / 12))
            }
        }
    }

    private var slotLabel: some View {
        Group {
            if (slotIndex - 1) % 16 == 0 {
                Text("\(slotIndex)")
                    .font(
                        .system(
                            size: max(6, min(10, minDimension * 0.35)),
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var ownerDots: some View {
        HStack(spacing: 1) {
            ForEach(owners.prefix(3)) { owner in
                Circle()
                    .fill(owner.color)
                    .frame(width: minDimension / 3.5, height: minDimension / 3.5)
            }
        }
        .padding(1)
    }

    private var gridLines: some View {
        let width = size.width
        let height = size.height
        return Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: width, y: 0))
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: height))

            if columnIndex == columnsCount - 1 {
                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
            }
            if rowIndex == rowsCount - 1 {
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: width, y: height))
            }
        }
        .stroke(gridLineColor, lineWidth: 0.8)
    }

    private var ownersHelpText: String {
        guard !owners.isEmpty else {
            return ""
        }
        return
            owners
            .map { "\($0.creatureName) · \($0.label)" }
            .joined(separator: "\n")
    }

    private var minDimension: CGFloat {
        min(size.width, size.height)
    }

    private var slotShade: Double {
        let normalized = Double(value) / 255.0
        if colorScheme == .dark {
            // In dark mode, keep the grid legible by mapping 0->dark, 255->light.
            return 0.005 + (normalized * 0.88)
        }
        return 1.0 - normalized
    }

    private var gridLineColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.2)
    }
}

extension Array where Element == UInt8 {
    fileprivate subscript(safe index: Int) -> UInt8? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
