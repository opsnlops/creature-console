import Common
import Darwin
import Foundation
import Network

struct SACNInterface: Identifiable, Hashable {
    let id: String
    let name: String
    let type: NWInterface.InterfaceType
    let addresses: [String]
    let nwInterface: NWInterface

    var displayName: String {
        let addressSummary = addresses.isEmpty ? "" : " (\(addresses.joined(separator: ", ")))"
        return "\(name) \(typeDescription)\(addressSummary)"
    }

    private var typeDescription: String {
        switch type {
        case .wifi:
            return "[Wi-Fi]"
        case .wiredEthernet:
            return "[Ethernet]"
        case .cellular:
            return "[Cellular]"
        case .loopback:
            return "[Loopback]"
        case .other:
            return "[Other]"
        @unknown default:
            return "[Unknown]"
        }
    }
}

enum SACNInterfaceCatalog {
    static func interfaceOptions(from path: NWPath) -> [SACNInterface] {
        let addresses = ipv4AddressesByInterface()
        var merged: [String: (interface: NWInterface, addresses: Set<String>)] = [:]

        for interface in path.availableInterfaces {
            let key = "\(interface.name)-\(interface.type)"
            let interfaceAddresses = addresses[interface.name] ?? []
            if var existing = merged[key] {
                existing.addresses.formUnion(interfaceAddresses)
                merged[key] = existing
            } else {
                merged[key] = (interface: interface, addresses: Set(interfaceAddresses))
            }
        }

        return merged.values.map { entry in
            SACNInterface(
                id: entry.interface.name,
                name: entry.interface.name,
                type: entry.interface.type,
                addresses: entry.addresses.sorted(),
                nwInterface: entry.interface
            )
        }
        .sorted { $0.name < $1.name }
    }

    private static func ipv4AddressesByInterface() -> [String: [String]] {
        var results: [String: [String]] = [:]
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            return results
        }

        defer { freeifaddrs(addrs) }

        var pointer = firstAddr
        while true {
            let addr = pointer.pointee
            defer {
                if let next = addr.ifa_next {
                    pointer = next
                }
            }

            guard let sa = addr.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else {
                if addr.ifa_next == nil { break }
                continue
            }

            let interfaceName = String(cString: addr.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sa,
                socklen_t(sa.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let address = stringFromCString(hostname)
                results[interfaceName, default: []].append(address)
            }

            if addr.ifa_next == nil { break }
        }

        return results
    }

    private static func stringFromCString(_ buffer: [CChar]) -> String {
        if let endIndex = buffer.firstIndex(of: 0) {
            let bytes = buffer[..<endIndex].map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        }
        let bytes = buffer.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

enum SACNMulticast {
    static func address(for universe: UInt16) -> String {
        let high = (universe >> 8) & 0xFF
        let low = universe & 0xFF
        return "239.255.\(high).\(low)"
    }
}

final class SACNReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.opsnlops.CreatureConsole.SACNReceiver")
    private var connectionGroup: NWConnectionGroup?

    func start(
        universe: UInt16,
        interface: NWInterface,
        onFrame: @escaping @Sendable (SACNFrame) -> Void,
        onState: @escaping @Sendable (NWConnectionGroup.State) -> Void
    ) throws {
        stop()

        let multicastAddress = SACNMulticast.address(for: universe)
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(multicastAddress),
            port: NWEndpoint.Port(rawValue: 5568) ?? .init(integerLiteral: 5568)
        )
        let multicastGroup = try NWMulticastGroup(for: [endpoint])
        let parameters = NWParameters.udp
        parameters.requiredInterface = interface
        parameters.allowLocalEndpointReuse = true

        let connectionGroup = NWConnectionGroup(with: multicastGroup, using: parameters)
        connectionGroup.setReceiveHandler(
            maximumMessageSize: 1500,
            rejectOversizedMessages: true
        ) { _, content, isComplete in
            guard isComplete, let content else {
                return
            }

            if let frame = SACNParser.parse(data: content) {
                onFrame(frame)
            }
        }
        connectionGroup.stateUpdateHandler = onState
        connectionGroup.start(queue: queue)
        self.connectionGroup = connectionGroup
    }

    func stop() {
        connectionGroup?.cancel()
        connectionGroup = nil
    }
}
