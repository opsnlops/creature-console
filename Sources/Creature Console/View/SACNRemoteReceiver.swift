/// TCP client for the remote sACN listener: NWConnection lifecycle, hello handshake,
/// and length-prefixed frame stream parsing.
/// Extracted from SACNUniverseMonitorView.swift (Phase 5 decomposition, issue #35).

import Common
import Foundation
import Network

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
