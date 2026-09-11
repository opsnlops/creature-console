import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import ServiceContextModule
import Testing
import WorldCore

@testable import creature_agent

@Suite("Beaky's mind in the world", .serialized)
struct WorldMindServiceTests {
    private let logger = Logger(label: "world-mind-tests")
    private let beaky = try! EntityID(validating: "character:beaky")
    private let april = try! EntityID(validating: "person:april")

    @Test("The cursor is durable, monotonic, and bound to one world")
    func cursorSurvivesRestartAndIgnoresOtherWorlds() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("world-cursor-\(UUID().uuidString)")
        let worldURL = URL(string: "http://world.test:8001/world/v1")!

        let cursor = WorldAgentCursor(stateDirectory: directory, worldURL: worldURL, logger: logger)
        #expect(await cursor.current() == nil)
        try await cursor.advance(to: 41)
        try await cursor.advance(to: 40)
        #expect(await cursor.current() == 41)

        let restarted = WorldAgentCursor(
            stateDirectory: directory, worldURL: worldURL, logger: logger)
        #expect(await restarted.current() == 41)

        let otherWorld = WorldAgentCursor(
            stateDirectory: directory,
            worldURL: URL(string: "http://fuzzball:8001/world/v1")!,
            logger: logger
        )
        #expect(await otherWorld.current() == nil)
    }

    @Test("A fresh mind starts from the present, answers April, and moves its cursor")
    func answersAprilFromTheSnapshot() async throws {
        let stub = StubWorld()
        let percept = try makePercept(text: "Beaky, are you awake?")
        await stub.script(connection: 0) { lastEventID in
            #expect(lastEventID == nil)
            return [
                .snapshot(latestSequence: 10),
                .delta(sequence: 11, envelope: try self.envelope(for: percept)),
                .delta(sequence: 12, envelope: try self.envelope(type: "test.unrelated")),
            ]
        }
        await stub.script(connection: 1) { lastEventID in
            #expect(lastEventID == 12)
            return []
        }
        try await Harness.run(
            stub: stub,
            logger: logger,
            respond: { transcript in
                #expect(transcript.last?.content == "Beaky, are you awake?")
                return "Wide awake, April!"
            }
        ) { harness in
            try await harness.runUntil {
                let responded = await stub.responses.count == 1
                let advanced = await harness.cursorAt() == 12
                return responded && advanced
            }
        }

        let posted = try #require(await stub.responses.first)
        #expect(posted.text == "Wide awake, April!")
        #expect(posted.inResponseToUtteranceID == percept.utterance.utteranceID)
        #expect(posted.responseID == CharacterMind.responseID(for: percept.considerationID))
    }

    @Test("A restart after the world accepted a turn never makes Beaky say it twice")
    func replayAfterCrashIsRecognised() async throws {
        let stub = StubWorld()
        let percept = try makePercept(text: "Say something once")
        let delta = ServerSentFrame.delta(sequence: 21, envelope: try envelope(for: percept))
        // The first connection dies after the POST but before the cursor moves (the harness
        // fails the cursor write once); the second replays the same percept.
        await stub.script(connection: 0) { _ in [.snapshot(latestSequence: 20), delta] }
        await stub.script(connection: 1) { lastEventID in
            #expect(lastEventID == 20)
            return [delta]
        }
        await stub.script(connection: 2) { lastEventID in
            #expect(lastEventID == 21)
            return []
        }
        let phrasing = PhrasingCounter()
        try await Harness.run(
            stub: stub,
            logger: logger,
            failFirstCursorWrite: true,
            respond: { _ in "Once, phrased attempt \(await phrasing.next())" }
        ) { harness in
            try await harness.runUntil { await harness.cursorAt() == 21 }
        }

        let responses = await stub.responses
        #expect(responses.count == 2)
        #expect(Set(responses.map(\.responseID)).count == 1)
        #expect(responses.map(\.text) == ["Once, phrased attempt 1", "Once, phrased attempt 2"])
        #expect(await stub.acceptedTexts == ["Once, phrased attempt 1"])
    }

    @Test("A world outage retries the same consideration without moving the cursor")
    func worldOutageRetriesFromTheCursor() async throws {
        let stub = StubWorld()
        let percept = try makePercept(text: "Still there?")
        let delta = ServerSentFrame.delta(sequence: 31, envelope: try envelope(for: percept))
        await stub.script(connection: 0) { _ in [.snapshot(latestSequence: 30), delta] }
        await stub.script(connection: 1) { lastEventID in
            #expect(lastEventID == 30)
            return [delta]
        }
        await stub.script(connection: 2) { _ in [] }
        await stub.failNextResponse(status: .serviceUnavailable)
        try await Harness.run(stub: stub, logger: logger, respond: { _ in "Right here." }) {
            harness in
            try await harness.runUntil { await harness.cursorAt() == 31 }
        }

        #expect(await stub.responses.count == 2)
        #expect(await stub.acceptedTexts == ["Right here."])
    }

    @Test("Silence is a decision: the cursor moves and nothing is posted")
    func silenceAdvancesWithoutPosting() async throws {
        let stub = StubWorld()
        let percept = try makePercept(text: "…")
        await stub.script(connection: 0) { _ in
            [
                .snapshot(latestSequence: 40),
                .delta(sequence: 41, envelope: try self.envelope(for: percept)),
            ]
        }
        await stub.script(connection: 1) { _ in [] }
        try await Harness.run(stub: stub, logger: logger, respond: { _ in "[silence]" }) {
            harness in
            try await harness.runUntil { await harness.cursorAt() == 41 }
        }

        #expect(await stub.responses.isEmpty)
    }

    @Test("Thinking and delivering happen inside one turn's trace context")
    func deliveryRunsInsideTheTurnSpan() async throws {
        // Before agent.turn existed, the POST ran after agent.consider returned and started a
        // fresh root trace; Honeycomb showed Beaky's reply disconnected from April's message.
        let percept = try makePercept(text: "Are we tracing?")
        let consideration = WorldConsideration(
            worldSequence: 1, envelope: try envelope(for: percept), percept: percept)
        let responder = ContextRecordingResponder()
        let client = HTTPClient(eventLoopGroupProvider: .singleton)
        let service = WorldMindService(
            subscriber: WorldPerceptSubscriber(
                worldURL: URL(string: "http://localhost:1/world/v1")!,
                characterID: beaky,
                cursor: WorldAgentCursor(
                    stateDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("unused-\(UUID().uuidString)"),
                    worldURL: URL(string: "http://localhost:1/world/v1")!,
                    logger: logger
                ),
                logger: logger
            ),
            mind: CharacterMind(
                configuration: CharacterMind.Configuration(
                    persona: "You are Beaky.",
                    characterID: beaky,
                    personID: april,
                    maximumReplyAge: 3_600,
                    maximumContextTurns: 20,
                    modelTimeout: .seconds(5),
                    modelName: "test-model"
                ),
                respond: { _ in "Yes, together." },
                logger: logger
            ),
            responder: responder,
            client: client,
            logger: logger
        )

        try await service.handle(consideration)
        try await client.shutdown()

        #expect(await responder.sawTurnContext == true)
        #expect(await responder.submitted?.text == "Yes, together.")
    }

    // MARK: - Fixtures

    private func makePercept(text: String) throws -> PersonUtterancePercept {
        try PersonUtterancePercept(
            characterID: beaky,
            utterance: PersonUtterance(
                conversationID: ConversationID(validating: "conversation:april-beaky"),
                speakerID: april,
                addresseeIDs: [beaky],
                text: text,
                modality: .typed,
                source: .communicatorComposition,
                sourceID: SourceID(validating: "communicator:test"),
                occurredAt: Date(),
                confidence: 1,
                trace: W3CTraceContext(
                    traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
            ),
            priorConversationItems: []
        )
    }

    private func envelope(for percept: PersonUtterancePercept) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            occurredAt: percept.utterance.occurredAt,
            source: EventSource(id: percept.utterance.sourceID, kind: "test"),
            subjectIDs: [april, beaky],
            epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: percept
        )
    }

    private func envelope(type: String) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: WorldEventType(validating: type),
            occurredAt: Date(),
            source: EventSource(id: SourceID(validating: "test:other"), kind: "test"),
            subjectIDs: [],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:]
        )
    }
}

// MARK: - Harness

/// A stub World on loopback, the mind wired to it, and a cursor in a scratch directory.
private struct Harness {
    let cursor: any WorldCursorStore
    let service: WorldMindService
    let client: HTTPClient

    /// Runs `body` with a live stub World and a mind pointed at it, then tears both down.
    static func run(
        stub: StubWorld,
        logger: Logger,
        failFirstCursorWrite: Bool = false,
        respond: @escaping CharacterMind.Respond,
        body: @escaping @Sendable (Harness) async throws -> Void
    ) async throws {
        try await stub.makeApplication().test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let worldURL = URL(string: "http://localhost:\(port)/world/v1")!
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("world-mind-\(UUID().uuidString)")
            let durable = WorldAgentCursor(
                stateDirectory: directory, worldURL: worldURL, logger: logger)
            let cursor: any WorldCursorStore =
                failFirstCursorWrite ? CrashingCursor(wrapping: durable) : durable
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            let beaky = try EntityID(validating: "character:beaky")
            let service = WorldMindService(
                subscriber: WorldPerceptSubscriber(
                    worldURL: worldURL,
                    characterID: beaky,
                    cursor: cursor,
                    logger: logger,
                    reconnectDelay: .milliseconds(20)
                ),
                mind: CharacterMind(
                    configuration: CharacterMind.Configuration(
                        persona: "You are Beaky.",
                        characterID: beaky,
                        personID: try EntityID(validating: "person:april"),
                        maximumReplyAge: 3_600,
                        maximumContextTurns: 20,
                        modelTimeout: .seconds(5),
                        modelName: "test-model"
                    ),
                    respond: respond,
                    logger: logger
                ),
                responder: WorldResponder(client: client, worldURL: worldURL, logger: logger),
                client: client,
                logger: logger
            )
            try await body(Harness(cursor: cursor, service: service, client: client))
        }
    }

    func cursorAt() async -> Int64? {
        await cursor.current()
    }

    /// Runs the mind until `condition` holds (or 10 s pass), then stops it.
    func runUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
        let run = Task { try await service.run() }
        let deadline = ContinuousClock.now + .seconds(10)
        var satisfied = false
        while ContinuousClock.now < deadline {
            if await condition() {
                satisfied = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        run.cancel()
        _ = try? await run.value
        if !satisfied {
            Issue.record("Condition not met within 10 seconds")
        }
    }
}

/// Fails the first cursor write, simulating a crash between the world accepting a turn and the
/// mind recording that it did. Later writes go through.
private actor CrashingCursor: WorldCursorStore {
    private let wrapped: WorldAgentCursor
    private var hasCrashed = false

    init(wrapping: WorldAgentCursor) {
        wrapped = wrapping
    }

    func current() async -> Int64? {
        await wrapped.current()
    }

    func advance(to sequence: Int64) async throws {
        if !hasCrashed, await wrapped.current() != nil {
            hasCrashed = true
            throw CrashingCursorError.simulatedCrash
        }
        try await wrapped.advance(to: sequence)
    }
}

private enum CrashingCursorError: Error {
    case simulatedCrash
}

/// Records whether `submit` ran inside a span context (the turn's) rather than at top level.
private actor ContextRecordingResponder: WorldTurnResponding {
    private(set) var sawTurnContext = false
    private(set) var submitted: CharacterUtteranceIntent?

    func submit(_ intent: CharacterUtteranceIntent) async throws -> WorldResponseOutcome {
        sawTurnContext = ServiceContext.current != nil
        submitted = intent
        return .accepted(
            CharacterDeliveryOutcome(
                attemptID: .generated(),
                responseID: intent.responseID,
                route: .communicator,
                state: .accepted,
                occurredAt: intent.createdAt
            )
        )
    }
}

private actor PhrasingCounter {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

// MARK: - Stub World

enum ServerSentFrame: Sendable {
    case snapshot(latestSequence: Int64)
    case delta(sequence: Int64, envelope: WorldEventEnvelope)

    var text: String {
        get throws {
            switch self {
            case .snapshot(let latestSequence):
                return
                    "event: snapshot\nid: \(latestSequence)\ndata: {\"latest_sequence\":\(latestSequence)}\n\n"
            case .delta(let sequence, let envelope):
                var stamped = envelope
                stamped.worldSequence = sequence
                let payload = try WorldJSON.makeEncoder().encode(
                    WorldDelta(event: stamped, changedFacts: []))
                return
                    "event: delta\nid: \(sequence)\ndata: \(String(decoding: payload, as: UTF8.self))\n\n"
            }
        }
    }
}

/// Serves scripted `/world/v1/stream` connections and records `/responses` submissions.
actor StubWorld {
    typealias Script = @Sendable (Int64?) async throws -> [ServerSentFrame]

    private(set) var connections: [Int64?] = []
    private(set) var responses: [CharacterUtteranceIntent] = []
    private(set) var acceptedTexts: [String] = []
    private var scripts: [Int: Script] = [:]
    private var pendingFailure: HTTPResponse.Status?
    private var acceptedByResponseID: [ResponseID: ConversationItem] = [:]

    func script(connection index: Int, _ script: @escaping Script) {
        scripts[index] = script
    }

    func failNextResponse(status: HTTPResponse.Status) {
        pendingFailure = status
    }

    private func frames(for lastEventID: Int64?) async throws -> [ServerSentFrame] {
        let index = connections.count
        connections.append(lastEventID)
        guard let script = scripts[index] else { return [] }
        return try await script(lastEventID)
    }

    private func record(_ intent: CharacterUtteranceIntent) throws -> (HTTPResponse.Status, Data) {
        responses.append(intent)
        if let status = pendingFailure {
            pendingFailure = nil
            return (status, Data())
        }
        if let existing = acceptedByResponseID[intent.responseID] {
            guard existing.text == intent.text else {
                let error = #"{"error":"invalid_request","message":"identity reused"}"#
                return (.badRequest, Data(error.utf8))
            }
            return (.ok, try encodeResult(.duplicate, item: existing, intent: intent))
        }
        let item = try ConversationItem(
            conversationID: intent.conversationID,
            authorID: intent.characterID,
            authorKind: .character,
            text: intent.text,
            createdAt: intent.createdAt,
            responseID: intent.responseID
        )
        acceptedByResponseID[intent.responseID] = item
        acceptedTexts.append(intent.text)
        return (.accepted, try encodeResult(.accepted, item: item, intent: intent))
    }

    private func encodeResult(
        _ disposition: CharacterDeliveryDisposition,
        item: ConversationItem,
        intent: CharacterUtteranceIntent
    ) throws -> Data {
        try WorldJSON.makeEncoder().encode(
            CharacterDeliveryResult(
                disposition: disposition,
                outcome: CharacterDeliveryOutcome(
                    attemptID: .generated(),
                    responseID: intent.responseID,
                    route: .communicator,
                    state: .accepted,
                    occurredAt: intent.createdAt
                ),
                conversationItem: item
            )
        )
    }

    nonisolated func makeApplication() -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        router.get("world/v1/stream") { request, _ in
            let lastEventID = request.headers.first { $0.name.canonicalName == "last-event-id" }
                .flatMap { Int64($0.value) }
            let frames = try await self.frames(for: lastEventID)
            return Response(
                status: .ok,
                headers: [.contentType: "text/event-stream; charset=utf-8"],
                body: ResponseBody { writer in
                    for frame in frames {
                        try await writer.write(ByteBuffer(string: try frame.text))
                    }
                    try await writer.finish(nil)
                }
            )
        }
        router.post("world/v1/conversations/:conversationID/responses") { request, _ in
            let body = try await request.body.collect(upTo: 1_048_576)
            let intent = try WorldJSON.makeDecoder().decode(
                CharacterUtteranceIntent.self, from: body)
            let (status, data) = try await self.record(intent)
            return Response(
                status: status,
                headers: [.contentType: "application/json"],
                body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
            )
        }
        return Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
    }
}
