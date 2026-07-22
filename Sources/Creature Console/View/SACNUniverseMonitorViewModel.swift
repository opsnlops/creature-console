/// View model for the sACN universe monitor: interface discovery (NWPathMonitor),
/// local/remote receiver lifecycle, and frame-coalescing state published to the view.
/// Extracted from SACNUniverseMonitorView.swift (Phase 5 decomposition, issue #35).

import Common
import Foundation
import Network
import Observation

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
@Observable
final class SACNUniverseMonitorViewModel {
    var interfaces: [SACNInterface] = []
    var selectedInterfaceID: String?
    var universe: Int = 1
    var isRunning: Bool = false
    var source: MonitorSource = .local {
        didSet {
            if oldValue != source, isRunning {
                restartReceiver()
            }
        }
    }
    var remoteHost: String = "" {
        didSet {
            if oldValue != remoteHost, source == .remote, isRunning {
                restartReceiver()
            }
        }
    }
    var remotePort: Int = 1963 {
        didSet {
            if oldValue != remotePort, source == .remote, isRunning {
                restartReceiver()
            }
        }
    }
    var slots: [UInt8] = Array(repeating: 0, count: 512)
    var status: MonitorStatus = .idle
    var lastPacketDate: Date?
    var lastSequence: UInt8?
    var packetCount: Int = 0

    enum MonitorStatus: Equatable {
        case idle
        case waitingForInterface
        case waitingForRemoteHost
        case connecting
        case waitingForPackets
        case listening
        case failed(String)
    }

    // Non-UI plumbing and frame-coalescing scratch state — observation is meaningless here.
    @ObservationIgnored private let receiver = SACNReceiver()
    @ObservationIgnored private let remoteReceiver = SACNRemoteReceiver()
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private let pathQueue = DispatchQueue(
        label: "io.opsnlops.CreatureConsole.SACNPathMonitor")
    @ObservationIgnored private let framePublishInterval: UInt64 = 20_000_000
    @ObservationIgnored private var pendingSlots: [UInt8] = Array(repeating: 0, count: 512)
    @ObservationIgnored private var pendingSequence: UInt8?
    @ObservationIgnored private var pendingPacketCount: Int = 0
    @ObservationIgnored private var pendingLastPacketDate: Date?
    @ObservationIgnored private var isFlushScheduled = false

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
