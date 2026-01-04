#if os(Linux)
    import Common
    import Foundation
    import NIOCore
    import NIOPosix

    struct LinuxInterface {
        let name: String
        let addresses: [String]
        let device: NIONetworkDevice
    }

    final class LinuxSACNRemoteProxy: @unchecked Sendable {
        fileprivate final class ClientState: @unchecked Sendable {
            let channel: Channel
            let universe: UInt16
            var udpChannel: Channel?
            var pendingWrites: Int = 0

            init(channel: Channel, universe: UInt16) {
                self.channel = channel
                self.universe = universe
            }
        }

        let lockedUniverse: UInt16?
        private let group: EventLoopGroup
        private let interface: LinuxInterface
        private let maxClients: Int
        private var clients: [ObjectIdentifier: ClientState] = [:]
        private let maxPendingWrites = 8

        init(
            group: EventLoopGroup, interface: LinuxInterface, lockedUniverse: UInt16?,
            maxClients: Int
        ) {
            self.group = group
            self.interface = interface
            self.lockedUniverse = lockedUniverse
            self.maxClients = maxClients
        }

        func attach(channel: Channel) -> EventLoopFuture<Void> {
            if clients.count >= maxClients {
                print("Viewer rejected: max clients reached (\(maxClients)).")
                return channel.close()
            }
            channel.closeFuture.whenComplete { [weak self] _ in
                self?.handleDisconnect(channel: channel)
            }
            return channel.pipeline.addHandler(HelloHandler(proxy: self))
        }

        private func handleDisconnect(channel: Channel) {
            let clientID = ObjectIdentifier(channel)
            if let client = clients[clientID] {
                stopUDPReceiver(client: client)
                clients[clientID] = nil
            }
        }

        fileprivate func handleHello(_ hello: SACNRemoteHello, on channel: Channel) {
            let universe = lockedUniverse ?? hello.universe
            print(
                "Viewer connected: \(hello.viewerName) (\(hello.viewerVersion)) universe \(universe)"
            )
            registerClient(universe: universe, on: channel)
        }

        fileprivate func handleInvalidHello(on channel: Channel) {
            print("Invalid hello from viewer. Closing connection.")
            _ = channel.close()
        }

        private func registerClient(universe: UInt16, on channel: Channel) {
            let clientID = ObjectIdentifier(channel)
            let client = ClientState(channel: channel, universe: universe)
            clients[clientID] = client
            startUDPReceiver(for: client)
        }

        private func startUDPReceiver(for client: ClientState) {
            let multicastAddress = SACNMulticast.address(for: client.universe)
            let bootstrap = DatagramBootstrap(group: group)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(SACNUDPHandler(proxy: self, client: client))
                }

            bootstrap.bind(host: "0.0.0.0", port: 5568).whenComplete {
                [weak self] (result: Result<Channel, Error>) in
                switch result {
                case .success(let channel):
                    client.udpChannel = channel
                    do {
                        let groupAddress = try SocketAddress(
                            ipAddress: multicastAddress, port: 5568)
                        if let multicastChannel = channel as? MulticastChannel {
                            multicastChannel.joinGroup(groupAddress, device: self?.interface.device)
                                .whenFailure { error in
                                    print("Failed to join multicast group: \(error)")
                                }
                        } else {
                            print("Multicast is not supported on this channel.")
                        }
                    } catch {
                        print("Failed to join multicast group: \(error)")
                    }
                case .failure(let error):
                    print("Failed to bind UDP socket: \(error)")
                }
            }
        }

        private func stopUDPReceiver(client: ClientState) {
            if let udpChannel = client.udpChannel {
                _ = udpChannel.close()
            }
        }

        fileprivate func send(rawData: Data, to client: ClientState) {
            guard rawData.count <= UInt16.max else {
                return
            }
            client.channel.eventLoop.execute {
                if !client.channel.isWritable || client.pendingWrites >= self.maxPendingWrites {
                    print("Viewer disconnected: slow client (not writable).")
                    _ = client.channel.close()
                    self.handleDisconnect(channel: client.channel)
                    return
                }
                client.pendingWrites += 1
                var buffer = client.channel.allocator.buffer(capacity: 2 + rawData.count)
                buffer.writeInteger(UInt16(rawData.count), endianness: .big)
                buffer.writeBytes(rawData)
                client.channel.writeAndFlush(buffer).whenComplete { [weak self] result in
                    client.pendingWrites = max(0, client.pendingWrites - 1)
                    if case .failure(let error) = result {
                        print("Viewer send failed: \(error)")
                        _ = client.channel.close()
                        self?.handleDisconnect(channel: client.channel)
                    }
                }
            }
        }
    }

    final class HelloHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
        typealias InboundIn = ByteBuffer
        private var buffer = Data()
        private let decoder = JSONDecoder()
        private let proxy: LinuxSACNRemoteProxy

        init(proxy: LinuxSACNRemoteProxy) {
            self.proxy = proxy
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var byteBuffer = unwrapInboundIn(data)
            if let bytes = byteBuffer.readBytes(length: byteBuffer.readableBytes) {
                buffer.append(contentsOf: bytes)
            }

            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)
                if let hello = try? decoder.decode(SACNRemoteHello.self, from: lineData),
                    hello.type == "hello"
                {
                    proxy.handleHello(hello, on: context.channel)
                } else {
                    proxy.handleInvalidHello(on: context.channel)
                }
                context.pipeline.removeHandler(self, promise: nil)
            }
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            proxy.handleInvalidHello(on: context.channel)
        }
    }

    final class SACNUDPHandler: ChannelInboundHandler {
        typealias InboundIn = AddressedEnvelope<ByteBuffer>
        private let proxy: LinuxSACNRemoteProxy
        private let client: LinuxSACNRemoteProxy.ClientState

        init(proxy: LinuxSACNRemoteProxy, client: LinuxSACNRemoteProxy.ClientState) {
            self.proxy = proxy
            self.client = client
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let envelope = unwrapInboundIn(data)
            var buffer = envelope.data
            guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
                return
            }
            let payload = Data(bytes)
            if let frame = SACNParser.parse(data: payload), frame.universe == client.universe {
                proxy.send(rawData: payload, to: client)
            }
        }
    }
#endif
