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

                @Option(help: "Maximum number of concurrent viewers")
                var maxClients: Int = 8

                @Flag(help: "List available interfaces and exit")
                var listInterfaces: Bool = false

                func run() async throws {
                    guard maxClients > 0 else {
                        throw failWithMessage("Max clients must be at least 1.")
                    }
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
                        lockedUniverse: universe.flatMap { UInt16($0) },
                        maxClients: maxClients
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

                @Option(help: "Maximum number of concurrent viewers")
                var maxClients: Int = 8

                @Flag(help: "List available interfaces and exit")
                var listInterfaces: Bool = false

                func run() async throws {
                    guard maxClients > 0 else {
                        throw failWithMessage("Max clients must be at least 1.")
                    }
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
                        lockedUniverse: universe.flatMap { UInt16($0) },
                        maxClients: maxClients
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
        fileprivate final class ClientState {
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
