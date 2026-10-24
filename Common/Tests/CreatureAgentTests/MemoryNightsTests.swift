import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing

@testable import creature_agent

/// The nights to remember, in line (#262): none skipped, none lost to a restart, and the night
/// in hand stops waiting on a batch while another waits behind it.
// A night that never starts would wait forever: the limit makes it a failure.
@Suite("The nights to remember", .timeLimit(.minutes(1)))
struct MemoryNightsTests {
    private let logger = Logger(label: "memory-nights-tests")
    private let first = MemoryNights.Night(day: "2026-10-22", run: "run-1")
    private let second = MemoryNights.Night(day: "2026-10-23", run: "run-2")
    private let third = MemoryNights.Night(day: "2026-10-24", run: "run-3")

    private func file() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "memory-nights-\(UUID().uuidString.lowercased())/memory-nights.json")
    }

    private func kept(in file: URL) throws -> [MemoryNights.Night] {
        try JSONDecoder().decode([MemoryNights.Night].self, from: Data(contentsOf: file))
    }

    @Test("A night that arrives while another is remembered waits behind it; none is skipped")
    func nightWaitsBehindTheOneInHand() async throws {
        let file = file()
        let nights = MemoryNights(file: file, logger: logger)
        let started = AsyncStream<MemoryNights.Night>.makeStream()
        let gate = AsyncStream<Void>.makeStream()
        let first = self.first
        let work: MemoryNights.Work = { night in
            started.continuation.yield(night)
            if night == first { for await _ in gate.stream { break } }
        }
        var order = started.stream.makeAsyncIterator()

        #expect(await nights.add(first, work) == false)
        #expect(await order.next() == first)
        #expect(await nights.isWaitedOn == false)
        // The second night arrives while the first is still out: it waits, and is kept.
        #expect(await nights.add(second, work))
        #expect(await nights.isWaitedOn)
        #expect(try kept(in: file) == [first, second])
        // Asked for again, the same night is not added twice.
        #expect(await nights.add(second, work))
        #expect(await nights.waiting == [first, second])

        gate.continuation.yield()
        gate.continuation.finish()
        #expect(await order.next() == second)
    }

    @Test("After a restart the night in progress comes first, then the ones that were waiting")
    func restartResumesTheLine() async throws {
        let file = file()
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([second, third]).write(to: file)
        let nights = MemoryNights(file: file, logger: logger)
        let started = AsyncStream<MemoryNights.Night>.makeStream()

        await nights.resume(inProgress: first) { started.continuation.yield($0) }

        var order = started.stream.makeAsyncIterator()
        #expect(await order.next() == first)
        #expect(await order.next() == second)
        #expect(await order.next() == third)
    }

    @Test("The night in progress is not put in line twice when it was already waiting")
    func inProgressIsNotDoubled() async throws {
        let file = file()
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([first, second]).write(to: file)
        let nights = MemoryNights(file: file, logger: logger)
        let started = AsyncStream<MemoryNights.Night>.makeStream()
        let gate = AsyncStream<Void>.makeStream()

        await nights.resume(inProgress: first) { night in
            started.continuation.yield(night)
            for await _ in gate.stream { break }
        }

        var order = started.stream.makeAsyncIterator()
        #expect(await order.next() == first)
        #expect(await nights.waiting == [first, second])
        gate.continuation.finish()
    }

    @Test("A batch waited on gives up, and is cancelled, when the next night is waiting")
    func batchGivesUpForTheNextNight() async throws {
        let cancelled = Cancelled()
        let router = Router(context: BasicRequestContext.self)
        router.get("v1/batches/:id") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(string: #"{"id":"batch-1","status":"in_progress"}"#)))
        }
        router.post("v1/batches/:id/cancel") { _, context in
            await cancelled.note(context.parameters.get("id") ?? "")
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: ResponseBody(
                    byteBuffer: ByteBuffer(string: #"{"id":"batch-1","status":"cancelling"}"#)))
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let logger = self.logger
        try await application.test(.live) { client in
            let port = try #require(client.port)
            let batches = OpenAIBatchClient(
                apiKey: "test", baseURL: URL(string: "http://localhost:\(port)/v1")!,
                logger: logger)
            await #expect(
                throws: OpenAIBatchError.unfinished(
                    "still in_progress with the next night waiting; cancelled")
            ) {
                try await batches.output(
                    of: "batch-1", every: .milliseconds(10),
                    deadline: Date().addingTimeInterval(3_600), giveUp: { true })
            }
        }
        #expect(await cancelled.ids == ["batch-1"])
    }
}

private actor Cancelled {
    private(set) var ids: [String] = []
    func note(_ id: String) { ids.append(id) }
}
