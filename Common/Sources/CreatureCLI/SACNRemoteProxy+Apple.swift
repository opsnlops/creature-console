#if canImport(Network)
    import Common
    import Foundation
    import Network

    final class InterfaceBox: @unchecked Sendable {
        var value: [SACNInterface] = []
    }

    final class SACNRemoteProxy: @unchecked Sendable {
        private struct ClientState {
            let connection: NWConnection
            var universe: UInt16?
            var buffer = Data()
            var pendingSends: Int = 0
        }

        private struct ReceiverState {
            let receiver: SACNReceiver
            var clients: Set<ObjectIdentifier>
        }

        let interface: SACNInterface
        let lockedUniverse: UInt16?
        private let maxClients: Int
        private let queue = DispatchQueue(label: "io.opsnlops.CreatureCLI.SACNRemoteProxy")
        private var clients: [ObjectIdentifier: ClientState] = [:]
        private var receivers: [UInt16: ReceiverState] = [:]
        private let maxPendingSends = 8

        init(interface: SACNInterface, lockedUniverse: UInt16?, maxClients: Int) {
            self.interface = interface
            self.lockedUniverse = lockedUniverse
            self.maxClients = maxClients
        }

        func attach(connection: NWConnection) {
            queue.async {
                if self.clients.count >= self.maxClients {
                    print("Viewer rejected: max clients reached (\(self.maxClients)).")
                    connection.cancel()
                    return
                }

                let clientID = ObjectIdentifier(connection)
                let state = ClientState(connection: connection, universe: nil)
                self.clients[clientID] = state
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
            let decoder = JSONDecoder()
            guard let hello = try? decoder.decode(SACNRemoteHello.self, from: data),
                hello.type == "hello"
            else {
                print("Invalid hello from viewer. Closing connection.")
                connection.cancel()
                return
            }

            let universe = lockedUniverse ?? hello.universe
            print(
                "Viewer connected: \(hello.viewerName) (\(hello.viewerVersion)) universe \(universe)"
            )

            guard var client = clients[clientID] else {
                connection.cancel()
                return
            }

            client.universe = universe
            clients[clientID] = client
            attachClient(clientID: clientID, to: universe)
        }

        private func send(_ payload: Data, to clientID: ObjectIdentifier) {
            guard var client = clients[clientID] else {
                return
            }
            guard payload.count <= UInt16.max else {
                return
            }
            if client.pendingSends >= maxPendingSends {
                print("Viewer disconnected: slow client (queue full).")
                client.connection.cancel()
                stop(clientID: clientID)
                return
            }
            var length = UInt16(payload.count).bigEndian
            var data = Data(bytes: &length, count: 2)
            data.append(payload)
            client.pendingSends += 1
            clients[clientID] = client
            client.connection.send(
                content: data,
                completion: .contentProcessed { [weak self] error in
                    self?.queue.async {
                        guard var client = self?.clients[clientID] else {
                            return
                        }
                        client.pendingSends = max(0, client.pendingSends - 1)
                        self?.clients[clientID] = client
                        if let error {
                            print("Viewer send failed: \(error.localizedDescription)")
                            client.connection.cancel()
                            self?.stop(clientID: clientID)
                        }
                    }
                })
        }

        private func stop(clientID: ObjectIdentifier) {
            guard var client = clients[clientID] else {
                return
            }
            if let universe = client.universe {
                detachClient(clientID: clientID, from: universe)
            }
            client.connection.cancel()
            clients[clientID] = nil
        }

        private func attachClient(clientID: ObjectIdentifier, to universe: UInt16) {
            if var receiverState = receivers[universe] {
                receiverState.clients.insert(clientID)
                receivers[universe] = receiverState
                return
            }

            let receiver = SACNReceiver()
            do {
                try receiver.start(
                    universe: universe,
                    interface: interface.nwInterface,
                    onPacket: { [weak self] packet in
                        self?.broadcast(packet.rawData, for: universe)
                    },
                    onState: { [weak self] state in
                        if case .failed(let error) = state {
                            print("sACN receiver failed: \(error.localizedDescription)")
                            self?.stopReceiver(for: universe)
                        }
                    }
                )
                receivers[universe] = ReceiverState(receiver: receiver, clients: [clientID])
            } catch {
                print("Failed to start sACN receiver: \(error.localizedDescription)")
                stop(clientID: clientID)
            }
        }

        private func detachClient(clientID: ObjectIdentifier, from universe: UInt16) {
            guard var receiverState = receivers[universe] else {
                return
            }
            receiverState.clients.remove(clientID)
            if receiverState.clients.isEmpty {
                receiverState.receiver.stop()
                receivers[universe] = nil
            } else {
                receivers[universe] = receiverState
            }
        }

        private func stopReceiver(for universe: UInt16) {
            if let receiverState = receivers[universe] {
                receiverState.receiver.stop()
            }
            receivers[universe] = nil
        }

        private func broadcast(_ payload: Data, for universe: UInt16) {
            guard let receiverState = receivers[universe] else {
                return
            }
            for clientID in receiverState.clients {
                send(payload, to: clientID)
            }
        }
    }
#endif
