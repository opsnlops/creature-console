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
