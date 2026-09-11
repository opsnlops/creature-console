import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

/// Drives the built `creature-agent` executable in world mode. The mind holds a stream to the
/// world open for its whole life; `systemctl stop` must not wait for that stream.
@Suite("Creature Agent black-box service", .serialized)
struct CreatureAgentBlackBoxTests {
    @Test("SIGTERM exits promptly while following the world")
    func gracefulShutdownCancelsTheStream() async throws {
        let stub = StreamHolder()
        try await makeWorldStub(stub).test(.live) { worldClient in
            let worldPort = try #require(worldClient.port)
            let configuration = try writeConfiguration(worldPort: worldPort)
            var agent = try AgentProcess(configuration: configuration)
            try await agent.start()
            try await stub.waitForSubscriber()

            let started = ContinuousClock.now
            let exit = await agent.stop()
            let elapsed = ContinuousClock.now - started
            #expect(exit == 0, "agent did not exit cleanly on SIGTERM while following the world")
            #expect(elapsed < .seconds(5), "agent took \(elapsed) to stop")
        }
    }

    /// A world whose stream sends a snapshot and then stays open with keep-alives.
    private func makeWorldStub(_ holder: StreamHolder)
        -> Application<RouterResponder<BasicRequestContext>>
    {
        let router = Router(context: BasicRequestContext.self)
        router.get("world/v1/stream") { _, _ in
            await holder.subscribed()
            return Response(
                status: .ok,
                headers: [.contentType: "text/event-stream; charset=utf-8"],
                body: ResponseBody { writer in
                    try await writer.write(
                        ByteBuffer(
                            string: "event: snapshot\nid: 7\ndata: {\"latest_sequence\":7}\n\n")
                    )
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

    private func writeConfiguration(worldPort: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-blackbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = directory.appendingPathComponent("agent.yaml")
        try """
        mode: world
        creatureId: 00000000-0000-0000-0000-000000000000
        llmBackend: local
        localLlmHost: 127.0.0.1
        localLlmPort: 1
        llmModel: none
        llmSystemPrompt: You are a test.
        worldUrl: http://localhost:\(worldPort)/world/v1
        stateDirectory: \(directory.path)
        areas: []
        """.write(to: configuration, atomically: true, encoding: .utf8)
        return configuration
    }
}

private actor StreamHolder {
    private var subscribers = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func subscribed() {
        subscribers += 1
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func waitForSubscriber() async throws {
        if subscribers > 0 { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    Task { await self.register(continuation) }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw BlackBoxError.agentNeverSubscribed
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func register(_ continuation: CheckedContinuation<Void, Never>) {
        if subscribers > 0 {
            continuation.resume()
        } else {
            waiters.append(continuation)
        }
    }
}

private struct AgentProcess {
    private let executable: URL
    private let configuration: URL
    private var process: Process?

    init(configuration: URL) throws {
        let candidate =
            ProcessInfo.processInfo.environment["CREATURE_AGENT_EXECUTABLE"].map {
                URL(fileURLWithPath: $0)
            }
            ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/creature-agent")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw BlackBoxError.missingExecutable(candidate.path)
        }
        executable = candidate
        self.configuration = configuration
    }

    mutating func start() async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "run", "--config-path", configuration.path, "--log-level", "warning",
            "--host", "127.0.0.1", "--port", "1", "--insecure",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OTEL_EXPORTER_OTLP_ENDPOINT")
        process.environment = environment
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        try process.run()
        self.process = process
    }

    /// SIGTERM, then the exit status; a process still alive after 15 s is killed and reported -1.
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

private enum BlackBoxError: Error {
    case missingExecutable(String)
    case agentNeverSubscribed
}
