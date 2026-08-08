#if canImport(Network)
    import Common
    import Foundation
    import Network

    /// Live-audio relay, Apple side: joins every RTP/RTCP multicast lane on the chosen
    /// interface once at startup and fans the raw datagrams out to TCP viewers, framed with
    /// `RTPRemoteStream`. The audio twin of `SACNRemoteProxy` — same hello handshake, same
    /// slow-client disconnect policy, but lanes are joined up front (every viewer wants the
    /// same streams) instead of per client.
    final class RTPRemoteProxy: @unchecked Sendable {
        private struct ClientState {
            let connection: NWConnection
            /// Dialog lanes this viewer asked for (music is always sent). Empty set = all.
            var channels: Set<Int>?
            var buffer = Data()
            var pendingSends: Int = 0
        }

        let interface: SACNInterface
        private let maxClients: Int
        private let queue = DispatchQueue(label: "io.opsnlops.CreatureCLI.RTPRemoteProxy")
        private var clients: [ObjectIdentifier: ClientState] = [:]
        private var connectionGroups: [NWConnectionGroup] = []
        // Live audio is ~1,700 small frames/s across 17 lanes — far chattier than sACN, so the
        // in-flight allowance is deeper before a viewer is declared slow and dropped.
        private let maxPendingSends = 256

        init(interface: SACNInterface, maxClients: Int) {
            self.interface = interface
            self.maxClients = maxClients
        }

        // MARK: - Multicast capture

        func startCapture() throws {
            let channels = Set(1...16)
            try queue.sync {
                var groups: [NWConnectionGroup] = []
                do {
                    groups.append(
                        try makeGroup(
                            port: RTPAudioConstants.rtpPort, kind: .rtp, channels: channels)
                    )
                    groups.append(
                        try makeGroup(
                            port: RTPAudioConstants.rtcpPort, kind: .rtcp, channels: channels)
                    )
                } catch {
                    groups.forEach { $0.cancel() }
                    throw error
                }
                connectionGroups = groups
                connectionGroups.forEach { $0.start(queue: queue) }
            }
        }

        private func makeGroup(
            port: UInt16,
            kind: RTPRemoteFrame.Kind,
            channels: Set<Int>
        ) throws -> NWConnectionGroup {
            var channelsByEndpoint: [NWEndpoint: Int] = [:]
            var endpoints: [NWEndpoint] = []
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw RTPRemoteProxyError.invalidPort
            }
            for channel in channels.sorted() + [RTPAudioConstants.backgroundMusicChannel] {
                let address =
                    channel == RTPAudioConstants.backgroundMusicChannel
                    ? RTPAudioConstants.backgroundMusicMulticastAddress
                    : RTPAudioConstants.dialogMulticastAddress(channel: channel)
                guard let address else { continue }
                let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(address), port: nwPort)
                channelsByEndpoint[endpoint] = channel
                endpoints.append(endpoint)
            }

            let multicastGroup = try NWMulticastGroup(for: endpoints, disableUnicast: true)
            let parameters = NWParameters.udp
            parameters.requiredInterface = interface.nwInterface
            parameters.allowLocalEndpointReuse = true

            let group = NWConnectionGroup(with: multicastGroup, using: parameters)
            group.setReceiveHandler(
                maximumMessageSize: RTPAudioConstants.maximumPacketSize,
                rejectOversizedMessages: true
            ) { [weak self] message, content, isComplete in
                guard
                    isComplete,
                    let content,
                    let localEndpoint = message.localEndpoint,
                    let channel = channelsByEndpoint[localEndpoint]
                else {
                    return
                }
                let frame = RTPRemoteFrame(channel: channel, kind: kind, payload: content)
                self?.queue.async { [weak self] in
                    self?.broadcast(frame)
                }
            }
            group.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    let name = kind == .rtp ? "RTP" : "RTCP"
                    print("\(name) multicast capture failed: \(error.localizedDescription)")
                }
            }
            return group
        }

        // MARK: - Viewers

        func attach(connection: NWConnection) {
            queue.async {
                if self.clients.count >= self.maxClients {
                    print("Viewer rejected: max clients reached (\(self.maxClients)).")
                    connection.cancel()
                    return
                }

                let clientID = ObjectIdentifier(connection)
                self.clients[clientID] = ClientState(connection: connection, channels: nil)
                connection.stateUpdateHandler = { [weak self] state in
                    self?.handleState(state, clientID: clientID)
                }
                connection.start(queue: self.queue)
                self.receiveHello(on: connection, clientID: clientID)
            }
        }

        private func handleState(_ state: NWConnection.State, clientID: ObjectIdentifier) {
            switch state {
            case .failed(let error):
                print("Viewer connection failed: \(error.localizedDescription)")
                stop(clientID: clientID)
            case .cancelled:
                stop(clientID: clientID)
            default:
                break
            }
        }

        private func receiveHello(on connection: NWConnection, clientID: ObjectIdentifier) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) {
                [weak self] data, _, isComplete, error in
                guard let self else { return }

                if var client = self.clients[clientID], let data {
                    client.buffer.append(data)
                    if let lineRange = client.buffer.firstRange(of: Data([0x0A])) {
                        let lineData = client.buffer.subdata(in: 0..<lineRange.lowerBound)
                        client.buffer.removeSubrange(0..<lineRange.upperBound)
                        self.clients[clientID] = client
                        self.handleHello(lineData, on: connection, clientID: clientID)
                        return
                    }
                    self.clients[clientID] = client
                } else if error != nil || isComplete {
                    self.stop(clientID: clientID)
                    return
                }

                if error == nil, !isComplete {
                    receiveHello(on: connection, clientID: clientID)
                }
            }
        }

        private func handleHello(
            _ data: Data,
            on connection: NWConnection,
            clientID: ObjectIdentifier
        ) {
            guard let hello = try? JSONDecoder().decode(RTPRemoteHello.self, from: data),
                hello.type == "hello"
            else {
                print("Invalid hello from viewer. Closing connection.")
                connection.cancel()
                return
            }

            guard var client = clients[clientID] else {
                connection.cancel()
                return
            }

            let wanted = Set(hello.channels.filter { (1...16).contains($0) })
            client.channels = wanted
            clients[clientID] = client
            let description = wanted.isEmpty ? "all channels" : "channels \(wanted.sorted())"
            print(
                "Viewer connected: \(hello.viewerName) (\(hello.viewerVersion)) — \(description)"
            )
        }

        private func broadcast(_ frame: RTPRemoteFrame) {
            guard !clients.isEmpty, let encoded = RTPRemoteStream.encode(frame) else {
                return
            }
            for (clientID, client) in clients {
                // Viewers that haven't finished the hello yet get nothing.
                guard let wanted = client.channels else { continue }
                if frame.channel != RTPAudioConstants.backgroundMusicChannel,
                    !wanted.isEmpty, !wanted.contains(frame.channel)
                {
                    continue
                }
                send(encoded, to: clientID)
            }
        }

        private func send(_ data: Data, to clientID: ObjectIdentifier) {
            guard var client = clients[clientID] else {
                return
            }
            if client.pendingSends >= maxPendingSends {
                print("Viewer disconnected: slow client (queue full).")
                client.connection.cancel()
                stop(clientID: clientID)
                return
            }
            client.pendingSends += 1
            clients[clientID] = client
            client.connection.send(
                content: data,
                completion: .contentProcessed { [weak self] error in
                    self?.queue.async { [weak self] in
                        self?.handleSendCompletion(clientID: clientID, error: error)
                    }
                })
        }

        private func handleSendCompletion(clientID: ObjectIdentifier, error: NWError?) {
            guard var client = clients[clientID] else {
                return
            }
            client.pendingSends = max(0, client.pendingSends - 1)
            clients[clientID] = client
            if let error {
                print("Viewer send failed: \(error.localizedDescription)")
                client.connection.cancel()
                stop(clientID: clientID)
            }
        }

        private func stop(clientID: ObjectIdentifier) {
            guard let client = clients[clientID] else {
                return
            }
            client.connection.cancel()
            clients[clientID] = nil
        }
    }

    enum RTPRemoteProxyError: LocalizedError {
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .invalidPort:
                "Unable to build multicast endpoints for the RTP/RTCP ports."
            }
        }
    }
#endif
