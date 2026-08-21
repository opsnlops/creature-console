import ArgumentParser
import Foundation
import Testing

@testable import Common
@testable import creature_cli

@Suite(.serialized)
struct ExchangesCommandTests {

    actor StubExchangeServer: ExchangeCommandClient {
        struct DownloadCall: Equatable, Sendable {
            let sessionId: String
            let format: ExchangeAudioFormat
        }

        private(set) var listCallCount = 0
        private(set) var fetchRequests: [String] = []
        private(set) var downloadCalls: [DownloadCall] = []

        var listResult: Result<[AdHocExchange], ServerError>
        var fetchResult: Result<AdHocExchange, ServerError>
        var downloadResult: Result<CreatureServerClient.ShareableSound, ServerError>

        init(
            listResult: Result<[AdHocExchange], ServerError> = .success([]),
            fetchResult: Result<AdHocExchange, ServerError> = .success(
                ExchangesCommandTests.makeExchange()),
            downloadResult: Result<CreatureServerClient.ShareableSound, ServerError> = .success(
                CreatureServerClient.ShareableSound(
                    data: Data("mp3-bytes".utf8),
                    suggestedFilename: "Beaky - 2026-08-20 - hello.mp3"))
        ) {
            self.listResult = listResult
            self.fetchResult = fetchResult
            self.downloadResult = downloadResult
        }

        func listAdHocExchanges() async -> Result<[AdHocExchange], ServerError> {
            listCallCount += 1
            return listResult
        }

        func getAdHocExchange(sessionId: String) async -> Result<AdHocExchange, ServerError> {
            fetchRequests.append(sessionId)
            return fetchResult
        }

        func downloadExchangeAudio(sessionId: String, format: ExchangeAudioFormat) async -> Result<
            CreatureServerClient.ShareableSound, ServerError
        > {
            downloadCalls.append(DownloadCall(sessionId: sessionId, format: format))
            return downloadResult
        }

        func recordedListCount() async -> Int {
            listCallCount
        }

        func recordedFetchRequests() async -> [String] {
            fetchRequests
        }

        func recordedDownloadCalls() async -> [DownloadCall] {
            downloadCalls
        }
    }

    static func makeExchange(
        sessionId: String = "session-1",
        status: ExchangeStatus = .ready
    ) -> AdHocExchange {
        AdHocExchange(
            sessionId: sessionId,
            creatureId: "beaky-1",
            creatureName: "Beaky",
            status: status,
            title: "Beaky - 20260820143012 - hello",
            transcript: "Hello there!",
            durationMs: 4200,
            createdAt: Date(timeIntervalSince1970: 1_755_700_000),
            finishedAt: Date(timeIntervalSince1970: 1_755_700_004),
            parts: [
                AdHocExchangePart(
                    index: 1, animationId: "anim-1", text: "Hello there!", durationMs: 4200)
            ])
    }

    private func makeListCommand() -> CreatureCLI.Exchanges.List {
        var command = CreatureCLI.Exchanges.List()
        command.globalOptions = GlobalOptions()
        return command
    }

    private func makeShowCommand(sessionId: String) -> CreatureCLI.Exchanges.Show {
        var command = CreatureCLI.Exchanges.Show()
        command.sessionId = sessionId
        command.globalOptions = GlobalOptions()
        return command
    }

    private func makeDownloadCommand(
        sessionId: String, output: String? = nil, overwrite: Bool = false,
        format: ExchangeAudioFormat = .mp3
    ) -> CreatureCLI.Exchanges.Download {
        var command = CreatureCLI.Exchanges.Download()
        command.sessionId = sessionId
        command.output = output
        command.overwrite = overwrite
        command.format = format
        command.globalOptions = GlobalOptions()
        return command
    }

    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchanges-command-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("list asks the server once and succeeds")
    func listCallsServer() async throws {
        let stub = StubExchangeServer(listResult: .success([Self.makeExchange()]))
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        try await makeListCommand().run()

        let listCount = await stub.recordedListCount()
        #expect(listCount == 1)

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("list failure exits non-zero with the server's message")
    func listFailureExits() async {
        let stub = StubExchangeServer(
            listResult: .failure(.serverError("mongo is on fire")))
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        let thrown = await #expect(throws: ExitCode.self) {
            try await makeListCommand().run()
        }
        #expect(thrown == .failure)

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("show passes the session id through")
    func showPassesSessionId() async throws {
        let stub = StubExchangeServer()
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        try await makeShowCommand(sessionId: "session-42").run()

        let requests = await stub.recordedFetchRequests()
        #expect(requests == ["session-42"])

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("show reports a missing exchange as a failure")
    func showNotFoundExits() async {
        let stub = StubExchangeServer(
            fetchResult: .failure(.notFound("No exchange found for that session")))
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        let thrown = await #expect(throws: ExitCode.self) {
            try await makeShowCommand(sessionId: "nope").run()
        }
        #expect(thrown == .failure)

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("download writes the file using the server's suggested name")
    func downloadWritesSuggestedName() async throws {
        let stub = StubExchangeServer()
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        try await makeDownloadCommand(sessionId: "session-1", output: scratch.path).run()

        let expected = scratch.appendingPathComponent("Beaky - 2026-08-20 - hello.mp3")
        let written = try Data(contentsOf: expected)
        #expect(written == Data("mp3-bytes".utf8))

        let calls = await stub.recordedDownloadCalls()
        #expect(calls == [.init(sessionId: "session-1", format: .mp3)])

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("download passes the requested format through")
    func downloadPassesFormat() async throws {
        let stub = StubExchangeServer(
            downloadResult: .success(
                CreatureServerClient.ShareableSound(
                    data: Data("wav-bytes".utf8), suggestedFilename: "session-1.wav")))
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        try await makeDownloadCommand(
            sessionId: "session-1", output: scratch.path, format: .wav
        ).run()

        let calls = await stub.recordedDownloadCalls()
        #expect(calls == [.init(sessionId: "session-1", format: .wav)])

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("download honors an explicit destination path")
    func downloadHonorsExplicitPath() async throws {
        let stub = StubExchangeServer()
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let destination = scratch.appendingPathComponent("keeper.mp3")
        try await makeDownloadCommand(sessionId: "session-1", output: destination.path).run()

        let written = try Data(contentsOf: destination)
        #expect(written == Data("mp3-bytes".utf8))

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("download refuses to clobber without --overwrite")
    func downloadRefusesToClobber() async throws {
        let stub = StubExchangeServer()
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let destination = scratch.appendingPathComponent("keeper.mp3")
        try Data("precious".utf8).write(to: destination)

        let thrown = await #expect(throws: ExitCode.self) {
            try await makeDownloadCommand(sessionId: "session-1", output: destination.path).run()
        }
        #expect(thrown == .failure)

        let untouched = try Data(contentsOf: destination)
        #expect(untouched == Data("precious".utf8))

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("download replaces the file with --overwrite")
    func downloadOverwrites() async throws {
        let stub = StubExchangeServer()
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let destination = scratch.appendingPathComponent("keeper.mp3")
        try Data("stale".utf8).write(to: destination)

        try await makeDownloadCommand(
            sessionId: "session-1", output: destination.path, overwrite: true
        ).run()

        let written = try Data(contentsOf: destination)
        #expect(written == Data("mp3-bytes".utf8))

        await CreatureCLI.Exchanges.resetServerFactory()
    }

    @Test("a still-streaming session reports the conflict and exits non-zero")
    func downloadWhileStreamingReportsConflict() async throws {
        let stub = StubExchangeServer(
            downloadResult: .failure(.conflict("Session is still streaming; try again shortly")))
        await CreatureCLI.Exchanges.useServerFactory { _ in stub }

        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let thrown = await #expect(throws: ExitCode.self) {
            try await makeDownloadCommand(sessionId: "session-1", output: scratch.path).run()
        }
        #expect(thrown == .failure)

        // Exactly one attempt — a 409 must not turn into a retry loop.
        let calls = await stub.recordedDownloadCalls()
        #expect(calls.count == 1)

        await CreatureCLI.Exchanges.resetServerFactory()
    }
}
