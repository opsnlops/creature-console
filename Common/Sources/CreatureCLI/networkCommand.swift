#if canImport(Network)
    import ArgumentParser
    import Common
    import Foundation
    import Network

    extension CreatureCLI {

        struct Network: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Network tooling for CreatureCLI",
                subcommands: [
                    SACNListen.self
                ]
            )

            struct SACNListen: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "Expose a remote sACN listener for the console viewer",
                    discussion:
                        "Opens a TCP port for the console to stream sACN frames captured on a local interface."
                )

                @Option(help: "Interface name to listen on (ex: en0)")
                var interface: String?

                @Option(help: "TCP port to listen on for remote viewers")
                var port: Int = 1963

                @Option(help: "Lock to a universe number (optional)")
                var universe: Int?

                @Flag(help: "List available interfaces and exit")
                var listInterfaces: Bool = false

                func run() async throws {
                    let interfaces = fetchInterfaces()

                    if listInterfaces {
                        printInterfaces(interfaces)
                        return
                    }

                    guard let selectedInterface = selectInterface(from: interfaces) else {
                        throw failWithMessage("No matching interfaces found.")
                    }

                    guard port > 0, port <= 65535 else {
                        throw failWithMessage("Invalid port. Must be 1-65535.")
                    }

                    let proxy = SACNRemoteProxy(
                        interface: selectedInterface,
                        lockedUniverse: universe.flatMap { UInt16($0) }
                    )

                    let endpointPort =
                        NWEndpoint.Port(rawValue: UInt16(port)) ?? .init(integerLiteral: 9011)
                    let listener = try NWListener(using: .tcp, on: endpointPort)
                    let queue = DispatchQueue(label: "io.opsnlops.CreatureCLI.SACNRemoteListener")

                    listener.newConnectionHandler = { connection in
                        proxy.attach(connection: connection)
                    }

                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            print("Listening on \(selectedInterface.name)")
                            print("Clients may connect on the following IP addresses:")
                            let allAddresses = SACNInterfaceCatalog.ipv4AddressesByInterface()
                                .values
                                .flatMap { $0 }
                                .sorted()
                            if allAddresses.isEmpty {
                                print("(no IPv4 addresses found)")
                            } else {
                                for address in allAddresses {
                                    print("- \(address)")
                                }
                            }
                            print("Remote viewer port: \(port)")
                            if let lockedUniverse = proxy.lockedUniverse {
                                print("Universe locked to \(lockedUniverse)")
                            } else {
                                print("Universe selected by viewer")
                            }
                        case .failed(let error):
                            print("Listener failed: \(error.localizedDescription)")
                        default:
                            break
                        }
                    }

                    listener.start(queue: queue)
                    try? await Task.sleep(nanoseconds: .max)
                }

                private func fetchInterfaces() -> [SACNInterface] {
                    let monitor = NWPathMonitor()
                    let queue = DispatchQueue(label: "io.opsnlops.CreatureCLI.SACNPathMonitor")
                    let semaphore = DispatchSemaphore(value: 0)
                    let box = InterfaceBox()

                    monitor.pathUpdateHandler = { path in
                        box.value = SACNInterfaceCatalog.interfaceOptions(from: path)
                        semaphore.signal()
                    }

                    monitor.start(queue: queue)
                    _ = semaphore.wait(timeout: .now() + 2)
                    monitor.cancel()

                    return box.value
                }

                private func printInterfaces(_ interfaces: [SACNInterface]) {
                    if interfaces.isEmpty {
                        print("No interfaces found.")
                        return
                    }
                    for interface in interfaces {
                        let addresses =
                            interface.addresses.isEmpty
                            ? ""
                            : " (\(interface.addresses.joined(separator: ", ")))"
                        print("\(interface.name) \(interface.type)\(addresses)")
                    }
                }

                private func selectInterface(from interfaces: [SACNInterface]) -> SACNInterface? {
                    if let name = interface {
                        return interfaces.first { $0.name == name }
                    }
                    return interfaces.first
                }
            }
        }
    }

    private final class InterfaceBox: @unchecked Sendable {
        var value: [SACNInterface] = []
    }

    private final class SACNRemoteProxy: @unchecked Sendable {
        let interface: SACNInterface
        let lockedUniverse: UInt16?
        private let receiver = SACNReceiver()
        private let queue = DispatchQueue(label: "io.opsnlops.CreatureCLI.SACNRemoteProxy")
        private var connection: NWConnection?
        private var buffer = Data()

        init(interface: SACNInterface, lockedUniverse: UInt16?) {
            self.interface = interface
            self.lockedUniverse = lockedUniverse
        }

        func attach(connection: NWConnection) {
            queue.async {
                self.stop()
                self.connection = connection
                connection.stateUpdateHandler = { [weak self] state in
                    self?.handleState(state)
                }
                connection.start(queue: self.queue)
                self.receiveHello(on: connection)
            }
        }

        private func handleState(_ state: NWConnection.State) {
            switch state {
            case .failed(let error):
                print("Viewer connection failed: \(error.localizedDescription)")
                stop()
            case .cancelled:
                stop()
            default:
                break
            }
        }

        private func receiveHello(on connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) {
                [weak self] data, _, isComplete, error in
                guard let self else { return }

                if let data {
                    buffer.append(data)
                    if let lineRange = buffer.firstRange(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: 0..<lineRange.lowerBound)
                        buffer.removeSubrange(0..<lineRange.upperBound)
                        handleHello(lineData, on: connection)
                        return
                    }
                }

                if error == nil, !isComplete {
                    receiveHello(on: connection)
                }
            }
        }

        private func handleHello(_ data: Data, on connection: NWConnection) {
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

            do {
                try receiver.start(
                    universe: universe,
                    interface: interface.nwInterface,
                    onPacket: { [weak self] packet in
                        self?.send(packet.rawData, on: connection)
                    },
                    onState: { [weak self] state in
                        if case .failed(let error) = state {
                            print("sACN receiver failed: \(error.localizedDescription)")
                            self?.stop()
                        }
                    }
                )
            } catch {
                print("Failed to start sACN receiver: \(error.localizedDescription)")
                connection.cancel()
            }
        }

        private func send(_ payload: Data, on connection: NWConnection) {
            guard payload.count <= UInt16.max else {
                return
            }
            var length = UInt16(payload.count).bigEndian
            var data = Data(bytes: &length, count: 2)
            data.append(payload)
            connection.send(content: data, completion: .contentProcessed { _ in })
        }

        private func stop() {
            receiver.stop()
            connection?.cancel()
            connection = nil
            buffer.removeAll(keepingCapacity: true)
        }
    }
#elseif os(Linux)
    import ArgumentParser
    import Common
    import Foundation
    import NIOCore
    import NIOPosix

    extension CreatureCLI {

        struct Network: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Network tooling for CreatureCLI",
                subcommands: [
                    SACNListen.self
                ]
            )

            struct SACNListen: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "Expose a remote sACN listener for the console viewer",
                    discussion:
                        "Opens a TCP port for the console to stream sACN frames captured on a local interface."
                )

                @Option(help: "Interface name to listen on (ex: eth0)")
                var interface: String?

                @Option(help: "TCP port to listen on for remote viewers")
                var port: Int = 1963

                @Option(help: "Lock to a universe number (optional)")
                var universe: Int?

                @Flag(help: "List available interfaces and exit")
                var listInterfaces: Bool = false

                func run() async throws {
                    let interfaces = try fetchInterfaces()

                    if listInterfaces {
                        printInterfaces(interfaces)
                        return
                    }

                    guard let selectedInterface = selectInterface(from: interfaces) else {
                        throw failWithMessage("No matching interfaces found.")
                    }

                    guard port > 0, port <= 65535 else {
                        throw failWithMessage("Invalid port. Must be 1-65535.")
                    }

                    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                    defer {
                        group.shutdownGracefully { error in
                            if let error {
                                print("EventLoopGroup shutdown error: \(error)")
                            }
                        }
                    }

                    let proxy = LinuxSACNRemoteProxy(
                        group: group,
                        interface: selectedInterface,
                        lockedUniverse: universe.flatMap { UInt16($0) }
                    )

                    let bootstrap = ServerBootstrap(group: group)
                        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                        .serverChannelOption(ChannelOptions.backlog, value: 256)
                        .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                        .childChannelInitializer { channel in
                            proxy.attach(channel: channel)
                        }

                    let channel = try await bootstrap.bind(host: "0.0.0.0", port: port).get()
                    print("Listening on \(selectedInterface.name)")
                    print("Clients may connect on the following IP addresses:")
                    let allAddresses = interfaces.flatMap { $0.addresses }.sorted()
                    if allAddresses.isEmpty {
                        print("(no IPv4 addresses found)")
                    } else {
                        for address in allAddresses {
                            print("- \(address)")
                        }
                    }
                    print("Remote viewer port: \(port)")
                    if let lockedUniverse = proxy.lockedUniverse {
                        print("Universe locked to \(lockedUniverse)")
                    } else {
                        print("Universe selected by viewer")
                    }

                    try await channel.closeFuture.get()
                }

                private func fetchInterfaces() throws -> [LinuxInterface] {
                    let devices = try System.enumerateDevices()
                    var merged: [String: (device: NIONetworkDevice, addresses: Set<String>)] = [:]

                    for device in devices {
                        guard let address = device.address else {
                            continue
                        }
                        guard case .v4 = address, let ip = address.ipAddress else {
                            continue
                        }
                        if var existing = merged[device.name] {
                            existing.addresses.insert(ip)
                            merged[device.name] = existing
                        } else {
                            merged[device.name] = (device: device, addresses: [ip])
                        }
                    }

                    return merged.map { entry in
                        LinuxInterface(
                            name: entry.key,
                            addresses: entry.value.addresses.sorted(),
                            device: entry.value.device
                        )
                    }
                    .sorted { $0.name < $1.name }
                }

                private func printInterfaces(_ interfaces: [LinuxInterface]) {
                    if interfaces.isEmpty {
                        print("No interfaces found.")
                        return
                    }
                    for interface in interfaces {
                        let addresses =
                            interface.addresses.isEmpty
                            ? ""
                            : " (\(interface.addresses.joined(separator: ", ")))"
                        print("\(interface.name)\(addresses)")
                    }
                }

                private func selectInterface(from interfaces: [LinuxInterface]) -> LinuxInterface? {
                    if let name = interface {
                        return interfaces.first { $0.name == name }
                    }
                    return interfaces.first
                }
            }
        }
    }

    private struct LinuxInterface {
        let name: String
        let addresses: [String]
        let device: NIONetworkDevice
    }

    private final class LinuxSACNRemoteProxy: @unchecked Sendable {
        let lockedUniverse: UInt16?
        private let group: EventLoopGroup
        private let interface: LinuxInterface
        private var connection: Channel?
        private var udpChannel: Channel?
        private var currentUniverse: UInt16?

        init(group: EventLoopGroup, interface: LinuxInterface, lockedUniverse: UInt16?) {
            self.group = group
            self.interface = interface
            self.lockedUniverse = lockedUniverse
        }

        func attach(channel: Channel) -> EventLoopFuture<Void> {
            if let existing = connection {
                _ = existing.close()
            }
            connection = channel
            channel.closeFuture.whenComplete { [weak self] _ in
                self?.handleDisconnect()
            }
            return channel.pipeline.addHandler(HelloHandler(proxy: self))
        }

        private func handleDisconnect() {
            connection = nil
            stopUDPReceiver()
        }

        fileprivate func handleHello(_ hello: SACNRemoteHello, on channel: Channel) {
            let universe = lockedUniverse ?? hello.universe
            currentUniverse = universe
            print(
                "Viewer connected: \(hello.viewerName) (\(hello.viewerVersion)) universe \(universe)"
            )
            startUDPReceiver(universe: universe, on: channel)
        }

        fileprivate func handleInvalidHello(on channel: Channel) {
            print("Invalid hello from viewer. Closing connection.")
            _ = channel.close()
        }

        private func startUDPReceiver(universe: UInt16, on channel: Channel) {
            stopUDPReceiver()

            let multicastAddress = SACNMulticast.address(for: universe)
            let bootstrap = DatagramBootstrap(group: group)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(SACNUDPHandler(proxy: self))
                }

            bootstrap.bind(host: "0.0.0.0", port: 5568).whenComplete {
                [weak self] (result: Result<Channel, Error>) in
                switch result {
                case .success(let channel):
                    self?.udpChannel = channel
                    do {
                        let groupAddress = try SocketAddress(
                            ipAddress: multicastAddress,
                            port: 5568
                        )
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

        private func stopUDPReceiver() {
            if let udpChannel {
                _ = udpChannel.close()
            }
            udpChannel = nil
        }

        fileprivate func send(rawData: Data) {
            guard rawData.count <= UInt16.max, let connection else {
                return
            }
            connection.eventLoop.execute {
                var buffer = connection.allocator.buffer(capacity: 2 + rawData.count)
                buffer.writeInteger(UInt16(rawData.count), endianness: .big)
                buffer.writeBytes(rawData)
                _ = connection.writeAndFlush(buffer)
            }
        }

        fileprivate func shouldSend(frame: SACNFrame) -> Bool {
            guard let currentUniverse else {
                return false
            }
            return frame.universe == currentUniverse
        }
    }

    private final class HelloHandler: ChannelInboundHandler, RemovableChannelHandler {
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

    private final class SACNUDPHandler: ChannelInboundHandler {
        typealias InboundIn = AddressedEnvelope<ByteBuffer>
        private let proxy: LinuxSACNRemoteProxy

        init(proxy: LinuxSACNRemoteProxy) {
            self.proxy = proxy
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let envelope = unwrapInboundIn(data)
            var buffer = envelope.data
            guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
                return
            }
            let payload = Data(bytes)
            if let frame = SACNParser.parse(data: payload), proxy.shouldSend(frame: frame) {
                proxy.send(rawData: payload)
            }
        }
    }
#else
    import ArgumentParser

    extension CreatureCLI {

        struct Network: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Network tooling for CreatureCLI"
            )

            func run() async throws {
                print("Network tools are not available on this platform.")
            }
        }
    }
#endif
