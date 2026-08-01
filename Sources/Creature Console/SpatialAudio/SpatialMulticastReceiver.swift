#if os(macOS)
    import Common
    import Foundation
    import Network

    final class SpatialMulticastReceiver: @unchecked Sendable {
        struct Subscription: Equatable, Sendable {
            let endpoint: NWEndpoint
            let channel: Int
        }

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
            try queue.sync {
                stopLocked()

                var newGroups: [NWConnectionGroup] = []
                do {
                    newGroups.append(
                        try makeGroup(
                            subscriptions: Self.subscriptions(
                                channels: channels,
                                port: RTPAudioConstants.rtpPort
                            ),
                            kind: .rtp,
                            interface: interface,
                            onPacket: onPacket,
                            onError: onError
                        )
                    )
                    newGroups.append(
                        try makeGroup(
                            subscriptions: Self.subscriptions(
                                channels: channels,
                                port: RTPAudioConstants.rtcpPort
                            ),
                            kind: .rtcp,
                            interface: interface,
                            onPacket: onPacket,
                            onError: onError
                        )
                    )
                } catch {
                    newGroups.forEach { $0.cancel() }
                    throw error
                }

                connectionGroups = newGroups
                connectionGroups.forEach { $0.start(queue: queue) }
            }
        }

        func stop() {
            queue.sync {
                stopLocked()
            }
        }

        private func stopLocked() {
            connectionGroups.forEach { $0.cancel() }
            connectionGroups.removeAll()
        }

        static func subscriptions(channels: Set<Int>, port: UInt16) -> [Subscription] {
            channels.filter { (1...16).contains($0) }.union([17]).sorted().compactMap {
                channel in
                let address =
                    channel == 17
                    ? RTPAudioConstants.backgroundMusicMulticastAddress
                    : RTPAudioConstants.dialogMulticastAddress(channel: channel)
                guard let address, let port = NWEndpoint.Port(rawValue: port) else {
                    return nil
                }
                return Subscription(
                    endpoint: .hostPort(host: NWEndpoint.Host(address), port: port),
                    channel: channel
                )
            }
        }

        private func makeGroup(
            subscriptions: [Subscription],
            kind: PacketKind,
            interface: NWInterface,
            onPacket: @escaping @Sendable (ReceivedPacket) -> Void,
            onError: @escaping @Sendable (String) -> Void
        ) throws -> NWConnectionGroup {
            let channelsByEndpoint = Dictionary(
                uniqueKeysWithValues: subscriptions.map { ($0.endpoint, $0.channel) }
            )
            let multicastGroup = try NWMulticastGroup(
                for: subscriptions.map(\.endpoint),
                disableUnicast: true
            )
            let parameters = NWParameters.udp
            parameters.requiredInterface = interface
            parameters.allowLocalEndpointReuse = true

            let group = NWConnectionGroup(with: multicastGroup, using: parameters)
            group.setReceiveHandler(
                maximumMessageSize: RTPAudioConstants.maximumPacketSize,
                rejectOversizedMessages: true
            ) { message, content, isComplete in
                guard
                    isComplete,
                    let content,
                    let localEndpoint = message.localEndpoint,
                    let channel = channelsByEndpoint[localEndpoint]
                else {
                    return
                }
                onPacket(ReceivedPacket(channel: channel, kind: kind, data: content))
            }
            group.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    let protocolName = kind == .rtp ? "RTP" : "RTCP"
                    onError("\(protocolName) multicast failed: \(error.localizedDescription)")
                }
            }
            return group
        }
    }
#endif
