#if os(Linux)
    import Common
    import Foundation
    import NIOConcurrencyHelpers
    import NIOCore
    import NIOPosix

    /// Live-audio relay, Linux side — the Pi deployment. One UDP socket per (lane, port) pair,
    /// each bound to its multicast group address so the socket itself identifies the channel
    /// and kind: no destination-address sniffing. Lanes are joined once at startup; TCP viewers
    /// fan out with a per-client channel filter from the hello.
    final class LinuxRTPRemoteProxy: @unchecked Sendable {
        final class ClientState: @unchecked Sendable {
            let channel: Channel
            /// Dialog lanes this viewer asked for (music always sent). Empty = all. `nil` until
            /// the hello lands.
            var wantedChannels: Set<Int>?
            var pendingWrites: Int = 0

            init(channel: Channel) {
                self.channel = channel
            }
        }

        private let group: EventLoopGroup
        private let interface: LinuxInterface
        private let maxClients: Int
        private let lock = NIOLock()
        private var clients: [ObjectIdentifier: ClientState] = [:]
        private var udpChannels: [Channel] = []
        // Live audio is ~1,700 small frames/s across 17 lanes — far chattier than sACN.
        private let maxPendingWrites = 256

        init(group: EventLoopGroup, interface: LinuxInterface, maxClients: Int) {
            self.group = group
            self.interface = interface
            self.maxClients = maxClients
        }

        // MARK: - Multicast capture

        func startCapture() async throws {
            var lanes: [(address: String, port: UInt16, channel: Int, kind: RTPRemoteFrame.Kind)] =
                []
            for channel in Array(1...16) + [RTPAudioConstants.backgroundMusicChannel] {
                let address =
                    channel == RTPAudioConstants.backgroundMusicChannel
                    ? RTPAudioConstants.backgroundMusicMulticastAddress
                    : RTPAudioConstants.dialogMulticastAddress(channel: channel)
                guard let address else { continue }
                lanes.append((address, RTPAudioConstants.rtpPort, channel, .rtp))
                lanes.append((address, RTPAudioConstants.rtcpPort, channel, .rtcp))
            }

            for lane in lanes {
                let bootstrap = DatagramBootstrap(group: group)
                    .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .channelInitializer { channel in
                        channel.pipeline.addHandler(
                            RTPUDPHandler(proxy: self, channelNumber: lane.channel, kind: lane.kind)
                        )
                    }

                // Binding to the group address itself filters this socket to its lane.
                let channel = try await bootstrap.bind(
                    host: lane.address, port: Int(lane.port)
                ).get()
                let groupAddress = try SocketAddress(
                    ipAddress: lane.address, port: Int(lane.port))
                guard let multicastChannel = channel as? MulticastChannel else {
                    channel.close(promise: nil)
                    throw RTPRemoteProxyError.multicastUnsupported
                }
                try await multicastChannel.joinGroup(
                    groupAddress, device: interface.device
                ).get()
                lock.withLock {
                    udpChannels.append(channel)
                }
            }
        }

        // MARK: - Viewers

        func attach(channel: Channel) -> EventLoopFuture<Void> {
            let rejected = lock.withLock { clients.count >= maxClients }
            if rejected {
                print("Viewer rejected: max clients reached (\(maxClients)).")
                return channel.close()
            }
            channel.closeFuture.whenComplete { [weak self] _ in
                self?.handleDisconnect(channel: channel)
            }
            return channel.pipeline.addHandler(RTPHelloHandler(proxy: self))
        }

        private func handleDisconnect(channel: Channel) {
            lock.withLock {
                clients[ObjectIdentifier(channel)] = nil
            }
        }

        fileprivate func handleHello(_ hello: RTPRemoteHello, on channel: Channel) {
            let wanted = Set(hello.channels.filter { (1...16).contains($0) })
            let client = ClientState(channel: channel)
            client.wantedChannels = wanted
            lock.withLock {
                clients[ObjectIdentifier(channel)] = client
            }
            let description = wanted.isEmpty ? "all channels" : "channels \(wanted.sorted())"
            print(
                "Viewer connected: \(hello.viewerName) (\(hello.viewerVersion)) — \(description)"
            )
        }

        fileprivate func handleInvalidHello(on channel: Channel) {
            print("Invalid hello from viewer. Closing connection.")
            _ = channel.close()
        }

        fileprivate func broadcast(_ frame: RTPRemoteFrame) {
            guard let encoded = RTPRemoteStream.encode(frame) else {
                return
            }
            let targets = lock.withLock {
                clients.values.filter { client in
                    guard let wanted = client.wantedChannels else { return false }
                    if frame.channel != RTPAudioConstants.backgroundMusicChannel,
                        !wanted.isEmpty, !wanted.contains(frame.channel)
                    {
                        return false
                    }
                    return true
                }
            }
            for client in targets {
                send(encoded, to: client)
            }
        }

        private func send(_ data: Data, to client: ClientState) {
            client.channel.eventLoop.execute {
                if !client.channel.isWritable || client.pendingWrites >= self.maxPendingWrites {
                    print("Viewer disconnected: slow client (not writable).")
                    _ = client.channel.close()
                    return
                }
                client.pendingWrites += 1
                var buffer = client.channel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                client.channel.writeAndFlush(buffer).whenComplete { result in
                    client.pendingWrites = max(0, client.pendingWrites - 1)
                    if case .failure(let error) = result {
                        print("Viewer send failed: \(error)")
                        _ = client.channel.close()
                    }
                }
            }
        }
    }

    enum RTPRemoteProxyError: Error, CustomStringConvertible {
        case multicastUnsupported

        var description: String {
            switch self {
            case .multicastUnsupported:
                "Multicast is not supported on this channel."
            }
        }
    }

    final class RTPHelloHandler: ChannelInboundHandler, RemovableChannelHandler,
        @unchecked Sendable
    {
        typealias InboundIn = ByteBuffer
        private var buffer = Data()
        private let decoder = JSONDecoder()
        private let proxy: LinuxRTPRemoteProxy

        init(proxy: LinuxRTPRemoteProxy) {
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
                if let hello = try? decoder.decode(RTPRemoteHello.self, from: lineData),
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

    final class RTPUDPHandler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = AddressedEnvelope<ByteBuffer>
        private let proxy: LinuxRTPRemoteProxy
        private let channelNumber: Int
        private let kind: RTPRemoteFrame.Kind

        init(proxy: LinuxRTPRemoteProxy, channelNumber: Int, kind: RTPRemoteFrame.Kind) {
            self.proxy = proxy
            self.channelNumber = channelNumber
            self.kind = kind
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let envelope = unwrapInboundIn(data)
            var buffer = envelope.data
            guard let bytes = buffer.readBytes(length: buffer.readableBytes),
                bytes.count <= RTPAudioConstants.maximumPacketSize
            else {
                return
            }
            proxy.broadcast(
                RTPRemoteFrame(channel: channelNumber, kind: kind, payload: Data(bytes))
            )
        }
    }
#endif
