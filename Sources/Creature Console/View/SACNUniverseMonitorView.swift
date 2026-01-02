import Common
import Network
import SwiftData
import SwiftUI

@MainActor
final class SACNUniverseMonitorViewModel: ObservableObject {
    @Published var interfaces: [SACNInterface] = []
    @Published var selectedInterfaceID: String?
    @Published var universe: Int = 1
    @Published var slots: [UInt8] = Array(repeating: 0, count: 512)
    @Published var status: MonitorStatus = .waitingForInterface
    @Published var lastPacketDate: Date?
    @Published var lastSequence: UInt8?
    @Published var packetCount: Int = 0

    enum MonitorStatus: Equatable {
        case idle
        case waitingForInterface
        case waitingForPackets
        case listening
        case failed(String)
    }

    private let receiver = SACNReceiver()
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "io.opsnlops.CreatureConsole.SACNPathMonitor")

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
    }

    func updateInterfaces(_ newInterfaces: [SACNInterface]) {
        interfaces = newInterfaces
        if let selectedInterfaceID,
            newInterfaces.contains(where: { $0.id == selectedInterfaceID })
        {
            return
        }
        selectedInterfaceID = newInterfaces.first?.id
        restartReceiver()
    }

    func setUniverse(_ newUniverse: Int) {
        let clamped = min(max(newUniverse, 1), 63999)
        guard universe != clamped else {
            return
        }
        universe = clamped
        restartReceiver()
    }

    func setSelectedInterface(id: String?) {
        guard selectedInterfaceID != id else {
            return
        }
        selectedInterfaceID = id
        restartReceiver()
    }

    func restartReceiver() {
        receiver.stop()
        slots = Array(repeating: 0, count: 512)
        lastPacketDate = nil
        lastSequence = nil
        packetCount = 0

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
                onFrame: { [weak self] frame in
                    guard frame.universe == universeValue else {
                        return
                    }
                    Task { @MainActor in
                        self?.slots = frame.slots
                        self?.lastPacketDate = Date()
                        self?.lastSequence = frame.sequence
                        self?.packetCount += 1
                        self?.status = .listening
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

    private var selectedInterface: SACNInterface? {
        interfaces.first { $0.id == selectedInterfaceID }
    }
}

struct SACNUniverseMonitorView: View {
    @AppStorage("activeUniverse") private var activeUniverse: Int = 1
    @Query(sort: \CreatureModel.name) private var creatures: [CreatureModel]
    @StateObject private var viewModel = SACNUniverseMonitorViewModel()
    @State private var universeString: String = ""
    @State private var slotOwners: [Int: [SlotOwner]] = [:]
    @State private var creatureLegend: [CreatureLegendEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            grid
            legend
        }
        .padding(16)
        .onAppear {
            universeString = String(activeUniverse)
            viewModel.setUniverse(activeUniverse)
            rebuildCreatureOverlay()
        }
        .onChange(of: activeUniverse) { _, newValue in
            universeString = String(newValue)
            viewModel.setUniverse(newValue)
        }
        .onChange(of: creatureSignature) { _, _ in
            rebuildCreatureOverlay()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                interfacePicker
                universeSelector
                Button("Use Active Universe") {
                    universeString = String(activeUniverse)
                    viewModel.setUniverse(activeUniverse)
                }
            }
            statusLine
        }
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

    private var universeSelector: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Universe")
                .font(.headline)
            TextField("1–63999", text: $universeString)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
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
        case .waitingForPackets:
            return .blue
        case .listening:
            return .green
        case .idle:
            return .secondary
        }
    }

    private var creatureSignature: String {
        creatures.map { creature in
            let inputs = creature.inputs
                .sorted { $0.slot < $1.slot }
                .map { "\($0.slot)-\($0.width)" }
                .joined(separator: ",")
            return "\(creature.id)|\(creature.channelOffset)|\(creature.mouthSlot)|\(inputs)"
        }
        .joined(separator: ";")
    }

    private func rebuildCreatureOverlay() {
        var slotOwners: [Int: [SlotOwner]] = [:]
        var legend: [CreatureLegendEntry] = []
        let creatureColors = creatureColorMap(for: creatures)

        for creature in creatures {
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

    private func creatureColorMap(for creatures: [CreatureModel]) -> [String: Color] {
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

private struct SACNUniverseGridView: View {
    let slots: [UInt8]
    let slotOwners: [Int: [SlotOwner]]
    private let columnsCount = 32
    private let rowsCount = 16

    var body: some View {
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
    }

    private var gridBackgroundColor: Color {
        #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
        #else
            return Color(.secondarySystemBackground)
        #endif
    }
}

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
