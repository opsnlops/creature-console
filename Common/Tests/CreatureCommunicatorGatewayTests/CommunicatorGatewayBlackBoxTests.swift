import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing
import WorldCore

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Drives the built `creature-communicator-gateway` executable as a child process. A Beaky
/// Communicator holds the conversation stream open for as long as it is foregrounded; a restart
/// must not wait for the phone to hang up.
@Suite("Communicator gateway black-box service", .serialized)
struct CommunicatorGatewayBlackBoxTests {
    @Test("SIGTERM exits promptly while a Communicator stream is open")
    func gracefulShutdownCutsOpenStreams() async throws {
        try await makeWorldStub().test(.live) { worldClient in
            let worldPort = try #require(worldClient.port)
            let port = try freeLoopbackPort()
            var gateway = try GatewayProcess(port: port, worldPort: worldPort)
            try await gateway.start()
            try await waitUntilListening(port)

            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            do {
                let response = try await client.execute(
                    HTTPClientRequest(
                        url:
                            "http://127.0.0.1:\(port)/communicator/v1/conversations/conversation:x/stream"
                    ),
                    deadline: .distantFuture
                )
                #expect(response.status == .ok)
                var iterator = response.body.makeAsyncIterator()
                let first = try await iterator.next()
                #expect(first.map { String(buffer: $0) }?.contains("event: ready") == true)

                let started = ContinuousClock.now
                let exit = await gateway.stop()
                let elapsed = ContinuousClock.now - started
                #expect(exit == 0, "gateway did not exit cleanly on SIGTERM with a stream open")
                #expect(elapsed < .seconds(5), "gateway took \(elapsed) to stop with a stream open")
            } catch {
                _ = await gateway.stop()
                try? await client.shutdown()
                throw error
            }
            try await client.shutdown()
        }
    }

    /// Health plus a conversation stream that says `ready` and then stays open forever.
    private func makeWorldStub() -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        router.get("world/v1/health") { _, _ in
            Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #"{"status":"ok"}"#)))
        }
        router.get("world/v1/conversations/:conversationID/stream") { _, _ in
            Response(
                status: .ok,
                headers: [.contentType: "text/event-stream; charset=utf-8"],
                body: ResponseBody { writer in
                    try await writer.write(ByteBuffer(string: "event: ready\ndata: {}\n\n"))
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(1))
                        try await writer.write(ByteBuffer(string: ": keep-alive\n\n"))
                    }
                }
            )
        }
        return Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
    }
}

private struct GatewayProcess {
    private let executable: URL
    private let port: Int
    private let worldPort: Int
    private var process: Process?

    init(port: Int, worldPort: Int) throws {
        let candidate =
            ProcessInfo.processInfo.environment["CREATURE_COMMUNICATOR_GATEWAY_EXECUTABLE"].map {
                URL(fileURLWithPath: $0)
            }
            ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/creature-communicator-gateway")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw BlackBoxError.missingExecutable(candidate.path)
        }
        executable = candidate
        self.port = port
        self.worldPort = worldPort
    }

    mutating func start() async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--host", "127.0.0.1",
            "--port", String(port),
            "--world-url", "http://localhost:\(worldPort)/world/v1",
            "--log-level", "warning",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OTEL_EXPORTER_OTLP_ENDPOINT")
        environment.removeValue(forKey: "CREATURE_COMMUNICATOR_GATEWAY_CONFIG")
        process.environment = environment
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        try process.run()
        self.process = process
    }

    /// Sends SIGTERM and returns the exit status. A process still running after 15 seconds is
    /// killed and reported as -1 so a regression fails the assertion instead of the test host.
    mutating func stop() async -> Int32 {
        guard let process else { return -1 }
        self.process = nil
        process.terminate()
        let deadline = ContinuousClock.now + .seconds(15)
        while process.isRunning {
            guard ContinuousClock.now < deadline else {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                return -1
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return process.terminationStatus
    }
}

private func waitUntilListening(_ port: Int) async throws {
    let deadline = ContinuousClock.now + .seconds(30)
    while !loopbackPortAccepts(port) {
        guard ContinuousClock.now < deadline else { throw BlackBoxError.serviceNeverListened }
        try await Task.sleep(for: .milliseconds(50))
    }
}

private func loopbackAddress(port: Int) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(port).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    return address
}

private func makeLoopbackSocket() -> Int32 {
    #if canImport(Glibc)
        let streamType = Int32(SOCK_STREAM.rawValue)
    #else
        let streamType = SOCK_STREAM
    #endif
    return socket(AF_INET, streamType, 0)
}

private func loopbackPortAccepts(_ port: Int) -> Bool {
    let descriptor = makeLoopbackSocket()
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    var address = loopbackAddress(port: port)
    return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            connect(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
        }
    }
}

private func freeLoopbackPort() throws -> Int {
    let descriptor = makeLoopbackSocket()
    guard descriptor >= 0 else { throw BlackBoxError.noFreePort }
    defer { close(descriptor) }
    var address = loopbackAddress(port: 0)
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0 else { throw BlackBoxError.noFreePort }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            getsockname(descriptor, sockaddrPointer, &length)
        }
    }
    guard named == 0 else { throw BlackBoxError.noFreePort }
    return Int(UInt16(bigEndian: address.sin_port))
}

private enum BlackBoxError: Error {
    case missingExecutable(String)
    case noFreePort
    case serviceNeverListened
}
