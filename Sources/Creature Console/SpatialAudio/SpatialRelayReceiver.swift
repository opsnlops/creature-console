#if os(macOS) || os(iOS) || os(tvOS)
    import Common
    import Foundation
    import Network

    /// TCP client for the CLI's live-audio relay (`creature-cli network rtp-listen`): connect,
    /// send the JSON hello naming the dialog channels we want, then turn the framed stream back
    /// into the same `SpatialReceivedPacket` values the multicast receiver produces. The
    /// pipeline downstream is identical — the relay is transparent by design.
    final class SpatialRelayReceiver: @unchecked Sendable {
        private let queue = DispatchQueue(
            label: "io.opsnlops.CreatureConsole.SpatialRelayReceiver"
        )
        private var connection: NWConnection?
        private var parser = RTPRemoteStream.Parser()

        func start(
            host: String,
            port: UInt16,
            channels: Set<Int>,
            onPacket: @escaping @Sendable (SpatialReceivedPacket) -> Void,
            onError: @escaping @Sendable (String) -> Void
        ) {
            stop()

            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                onError("Invalid relay port \(port).")
                return
            }
            let connection = NWConnection(
                host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.sendHello(channels: channels, over: connection, onError: onError)
                    self?.receiveLoop(on: connection, onPacket: onPacket, onError: onError)
                case .failed(let error):
                    onError("Relay connection failed: \(error.localizedDescription)")
                case .waiting(let error):
                    onError("Relay unreachable: \(error.localizedDescription)")
                default:
                    break
                }
            }
            connection.start(queue: queue)
            self.connection = connection
        }

        func stop() {
            queue.sync {
                connection?.cancel()
                connection = nil
                parser = RTPRemoteStream.Parser()
            }
        }

        private func sendHello(
            channels: Set<Int>,
            over connection: NWConnection,
            onError: @escaping @Sendable (String) -> Void
        ) {
            let hello = RTPRemoteHello(
                viewerName: "Creature Console Spatial Monitor",
                viewerVersion: appVersion(),
                channels: channels.sorted()
            )
            do {
                var message = try JSONEncoder().encode(hello)
                message.append(0x0A)
                connection.send(content: message, completion: .contentProcessed { _ in })
            } catch {
                onError("Unable to encode relay hello: \(error.localizedDescription)")
            }
        }

        private func receiveLoop(
            on connection: NWConnection,
            onPacket: @escaping @Sendable (SpatialReceivedPacket) -> Void,
            onError: @escaping @Sendable (String) -> Void
        ) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                [weak self] data, _, isComplete, error in
                guard let self else { return }

                if let data, !data.isEmpty {
                    let intact = self.parser.append(data) { frame in
                        onPacket(
                            SpatialReceivedPacket(
                                channel: frame.channel,
                                kind: frame.kind == .rtp ? .rtp : .rtcp,
                                data: frame.payload
                            ))
                    }
                    guard intact else {
                        onError("Relay stream corrupted — disconnecting.")
                        connection.cancel()
                        return
                    }
                }

                if let error {
                    onError("Relay receive failed: \(error.localizedDescription)")
                } else if isComplete {
                    onError("Relay closed the connection.")
                } else {
                    self.receiveLoop(on: connection, onPacket: onPacket, onError: onError)
                }
            }
        }

        private func appVersion() -> String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        }
    }
#endif
