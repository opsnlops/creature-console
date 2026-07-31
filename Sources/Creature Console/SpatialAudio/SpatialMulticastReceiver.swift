#if os(macOS)
    import Common
    import Foundation
    import Network

    final class SpatialMulticastReceiver: @unchecked Sendable {
        enum PacketKind: Sendable {
            case rtp
            case rtcp
        }

        struct ReceivedPacket: Sendable {
            let channel: Int
            let kind: PacketKind
            let data: Data
        }

        private let queue = DispatchQueue(
            label: "io.opsnlops.CreatureConsole.SpatialMulticastReceiver"
        )
        private var connectionGroups: [NWConnectionGroup] = []

        func start(
            channels: Set<Int>,
            interface: NWInterface,
            onPacket: @escaping @Sendable (ReceivedPacket) -> Void,
            onError: @escaping @Sendable (String) -> Void
        ) throws {
            stop()

            let activeChannels = channels.filter { (1...16).contains($0) }.union([17])
            var newGroups: [NWConnectionGroup] = []
            do {
                for channel in activeChannels.sorted() {
                    let address =
                        channel == 17
                        ? RTPAudioConstants.backgroundMusicMulticastAddress
                        : RTPAudioConstants.dialogMulticastAddress(channel: channel)!
                    newGroups.append(
                        try makeGroup(
                            address: address,
                            port: RTPAudioConstants.rtpPort,
                            channel: channel,
                            kind: .rtp,
                            interface: interface,
                            onPacket: onPacket,
                            onError: onError
                        )
                    )
                    newGroups.append(
                        try makeGroup(
                            address: address,
                            port: RTPAudioConstants.rtcpPort,
                            channel: channel,
                            kind: .rtcp,
                            interface: interface,
                            onPacket: onPacket,
                            onError: onError
                        )
                    )
                }
            } catch {
                newGroups.forEach { $0.cancel() }
                throw error
            }

            connectionGroups = newGroups
            connectionGroups.forEach { $0.start(queue: queue) }
        }

        func stop() {
            connectionGroups.forEach { $0.cancel() }
            connectionGroups.removeAll()
        }

        private func makeGroup(
            address: String,
            port: UInt16,
            channel: Int,
            kind: PacketKind,
            interface: NWInterface,
            onPacket: @escaping @Sendable (ReceivedPacket) -> Void,
            onError: @escaping @Sendable (String) -> Void
        ) throws -> NWConnectionGroup {
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(address),
                port: NWEndpoint.Port(rawValue: port)!
            )
            let multicastGroup = try NWMulticastGroup(for: [endpoint])
            let parameters = NWParameters.udp
            parameters.requiredInterface = interface
            parameters.allowLocalEndpointReuse = true

            let group = NWConnectionGroup(with: multicastGroup, using: parameters)
            group.setReceiveHandler(
                maximumMessageSize: RTPAudioConstants.maximumPacketSize,
                rejectOversizedMessages: true
            ) { _, content, isComplete in
                guard isComplete, let content else {
                    return
                }
                onPacket(ReceivedPacket(channel: channel, kind: kind, data: content))
            }
            group.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    onError("Channel \(channel) multicast failed: \(error.localizedDescription)")
                }
            }
            return group
        }
    }
#endif
