import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import Testing
import WorldCore

@testable import creature_world

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// Drives the built `creature-world` executable as a child process over real TCP, the way an
/// adapter or World Viewer on the LAN would. Everything else in this test target talks to
/// Hummingbird in-process; this is the proof that the Linux service itself accepts, streams,
/// deduplicates, resumes without a gap, and survives being killed.
@Suite(
    "Creature World black-box service",
    .serialized,
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run black-box service tests")
)
struct CreatureWorldBlackBoxTests {
    @Test("The Linux service streams, resumes without a gap, and survives a process restart")
    func serviceLifecycle() async throws {
        let uri = try #require(mongoTestURI)
        let port = try freeLoopbackPort()
        let client = HTTPClient(eventLoopGroupProvider: .singleton)
        let api = WorldServiceAPI(client: client, port: port)
        defer { Task { try? await client.shutdown() } }
        let sourceID = try SourceID(validating: "blackbox:\(UUID().uuidString.lowercased())")

        // The world is told to assume April is home and audible, as a deployment would be until
        // real presence exists, so a staged turn goes to the physical stage.
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "creature-world-blackbox-\(UUID().uuidString).json")
        try Data(
            """
            {"presence": {"assumed": {"person:april": {"state": "home", "physically_audible": true}}}}
            """.utf8
        ).write(to: configURL)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let service = try CreatureWorldProcess(port: port, mongoURI: uri, configURL: configURL)
        try await service.start()
        try await api.waitUntilHealthy()

        // A fresh stream begins with a snapshot; the first event then arrives as a live delta.
        let snapshotStream = try await api.openStream(lastEventID: nil)
        let snapshot = try await snapshotStream.next()
        #expect(snapshot.event == "snapshot")
        let latestSequence = try #require(snapshot.id.flatMap(Int64.init))

        let first = try makeEvent(sourceID: sourceID)
        let firstAcceptance = try await api.post(first)
        #expect(firstAcceptance.status == .accepted)
        #expect(firstAcceptance.body.disposition == .accepted)
        let firstSequence = try #require(firstAcceptance.body.event.worldSequence)
        #expect(firstSequence > latestSequence)

        let firstDelta = try await snapshotStream.next(from: sourceID)
        #expect(firstDelta.event == "delta")
        #expect(firstDelta.id == String(firstSequence))

        // History reads back by sequence and duplicate submission is idempotent. Other suites
        // share this database, so only this run's source is asserted on.
        let page = try await api.events(after: firstSequence - 1, from: sourceID)
        #expect(page.map(\.eventID) == [first.eventID])

        let duplicate = try await api.post(first)
        #expect(duplicate.status == .ok)
        #expect(duplicate.body.disposition == .duplicateEvent)
        #expect(duplicate.body.event.worldSequence == firstSequence)
        snapshotStream.cancel()

        // An event accepted while no stream was open is replayed on reconnect, then live deltas
        // continue — no snapshot, no gap.
        let second = try makeEvent(sourceID: sourceID)
        let secondSequence = try #require(try await api.post(second).body.event.worldSequence)
        #expect(secondSequence > firstSequence)

        let resumedStream = try await api.openStream(lastEventID: firstSequence)
        let replayed = try await resumedStream.next(from: sourceID)
        #expect(replayed.event == "event")
        #expect(replayed.id == String(secondSequence))
        #expect(replayed.eventID == second.eventID)

        let third = try makeEvent(sourceID: sourceID)
        let thirdSequence = try #require(try await api.post(third).body.event.worldSequence)
        let thirdDelta = try await resumedStream.next(from: sourceID)
        #expect(thirdDelta.event == "delta")
        #expect(thirdDelta.id == String(thirdSequence))
        #expect(thirdDelta.eventID == third.eventID)
        resumedStream.cancel()

        // April speaks and Beaky answers through the same service; both turns become one
        // ordered conversation and the answer reaches a listener already on the stream.
        let conversationID = try ConversationID(
            validating: "conversation:blackbox-\(UUID().uuidString.lowercased())"
        )
        let conversationStream = try await api.openConversationStream(conversationID)
        #expect(try await conversationStream.next().event == "ready")
        // The utterance becomes a conversation.person_utterance world event under its own
        // source, so the event assertions above stay scoped to this run's synthetic events.
        let utterance = try makeUtterance(
            in: conversationID,
            sourceID: SourceID(validating: "communicator:blackbox")
        )
        let ingress = try await api.post(utterance)
        #expect(ingress.status == .accepted)
        #expect(ingress.body.disposition == .accepted)
        #expect(
            try await conversationStream.next().id == ingress.body.conversationItem.itemID.rawValue)
        let intent = try makeIntent(in: conversationID, answering: utterance)
        let response = try await api.post(intent)
        #expect(response.status == .accepted)
        #expect(response.body.disposition == .accepted)
        // With April assumed home, a hand-cast turn is put on the physical stage; the world has
        // no voice of its own, so the outcome is an honest failure and the words still reach
        // conversation subscribers.
        #expect(response.body.outcome.route == .physicalSpeech)
        #expect(response.body.outcome.state == .failed)
        #expect(response.body.outcome.errorCode == "physical_speech_not_connected")
        #expect(
            try await conversationStream.next().id == response.body.conversationItem.itemID.rawValue
        )
        let replayedResponse = try await api.post(intent)
        #expect(replayedResponse.status == .ok)
        #expect(replayedResponse.body.disposition == .duplicate)

        // A mind that asks for the stage first is put in the room (assumed presence), performs
        // the turn itself, and records it; the words still reach conversation subscribers.
        let stagedIntent = try makeIntent(
            in: conversationID, answering: utterance, text: "And I can say it out loud.",
            secondsLater: 2)
        let stage = try await api.stage(stagedIntent)
        #expect(stage.disposition == .decided)
        #expect(stage.decision.route == .physicalSpeech)
        #expect(stage.decision.presence.basis == .assumed)
        let performance = try CharacterPerformance(
            intent: stagedIntent,
            attemptID: stage.decision.attemptID,
            outcome: CharacterPerformanceReport(state: .performed, providerReference: "animation:1")
        )
        let performed = try await api.post(performance)
        #expect(performed.status == .accepted)
        #expect(performed.body.outcome.route == .physicalSpeech)
        #expect(performed.body.outcome.state == .performed)
        #expect(
            try await conversationStream.next().id
                == performed.body.conversationItem.itemID.rawValue)
        #expect(try await api.stage(stagedIntent).disposition == .alreadyDelivered)
        conversationStream.cancel()

        // Two minds log in; April's next words open a scene instead of a solo answer. The world
        // offers the floor to Beaky, then Mango, records what they say as conversation items,
        // closes when both pass, and — with no Creature Server configured here — records that
        // the performance could not happen rather than losing the scene.
        let beaky = try EntityID(validating: "character:beaky")
        let mango = try EntityID(validating: "character:mango")
        let beakySession = try await api.login(beaky, host: "blackbox-beaky")
        let mangoSession = try await api.login(mango, host: "blackbox-mango")
        #expect(beakySession.disposition == .loggedIn)
        #expect(mangoSession.disposition == .loggedIn)

        // Logging in is something the world now knows: each login becomes a presence fact, and
        // the next thing April says carries those facts (and her own assumed presence) to the
        // mind that hears it.
        let mangoPresence = try await api.waitForFact(
            about: mango, predicate: WorldFacts.characterRegion)
        #expect(mangoPresence.value == .string("region:home"))
        #expect(mangoPresence.epistemic.type == .observed)
        _ = try await api.waitForFact(about: beaky, predicate: WorldFacts.characterRegion)

        let sceneUtterance = try makeUtterance(
            in: conversationID, sourceID: SourceID(validating: "communicator:blackbox"),
            text: "What do you two think is in the box?")
        let sceneIngress = try await api.post(sceneUtterance)
        #expect(sceneIngress.status == .accepted)
        let sceneID = try #require(sceneIngress.body.percept.sceneID)
        let known = sceneIngress.body.percept.worldFacts
        #expect(known.count <= WorldKnowledgeLimits.maximumFacts)
        #expect(
            Set(known.map { "\($0.subjectID.rawValue) \($0.predicate)" }).isSuperset(of: [
                "character:beaky \(WorldFacts.characterRegion)",
                "character:mango \(WorldFacts.characterRegion)",
                "person:april \(WorldFacts.personState)",
            ]))
        #expect(
            known.first { $0.subjectID == sceneUtterance.speakerID }?.epistemic.type == .assumed)

        var scene = try #require(try await api.scene(sceneID))
        #expect(scene.participants == [beaky, mango])
        #expect(scene.floor?.characterID == beaky)
        let beakyTurn = try await api.submitTurn(
            to: sceneID,
            SceneTurnSubmission(
                characterID: beaky, responseID: try #require(scene.floor?.responseID),
                sessionID: beakySession.session.sessionID, text: "Servos, I hope!"))
        #expect(beakyTurn.status == .accepted)
        #expect(beakyTurn.body.scene.floor?.characterID == mango)

        // A mind without Mango's session cannot speak as Mango.
        let impostor = try await api.submitTurnStatus(
            to: sceneID,
            SceneTurnSubmission(
                characterID: mango,
                responseID: try #require(beakyTurn.body.scene.floor?.responseID),
                sessionID: nil, text: "It is me, Mango."))
        #expect(impostor == .conflict)

        let mangoTurn = try await api.submitTurn(
            to: sceneID,
            SceneTurnSubmission(
                characterID: mango,
                responseID: try #require(beakyTurn.body.scene.floor?.responseID),
                sessionID: mangoSession.session.sessionID, text: "It is always heat sinks."))
        scene = mangoTurn.body.scene
        for _ in 0..<2 {
            let floor = try #require(scene.floor)
            let session = floor.characterID == beaky ? beakySession : mangoSession
            scene = try await api.submitTurn(
                to: sceneID,
                SceneTurnSubmission(
                    characterID: floor.characterID, responseID: floor.responseID,
                    sessionID: session.session.sessionID, text: nil)
            ).body.scene
        }
        #expect(scene.closeReason == .everyonePassed)
        #expect(scene.state == .abandoned)
        #expect(scene.performance?.state == .failed)
        #expect(scene.performance?.errorCode == "creature_server_not_configured")
        let spokenResponses = scene.spokenTurns.map(\.responseID)
        let sceneItems = try await api.conversationItems(in: conversationID).filter {
            $0.responseID.map(spokenResponses.contains) ?? false
        }
        #expect(sceneItems.map(\.authorID) == [beaky, mango])
        #expect(sceneItems.map(\.text) == ["Servos, I hope!", "It is always heat sinks."])
        let sceneEvents = try await api.events(
            after: thirdSequence, from: SourceID(validating: "world:scenes")
        ).filter { $0.payload["scene_id"] == .string(sceneID.rawValue) }
        #expect(
            sceneEvents.map(\.type.rawValue).prefix(3) == [
                "scene.opened", "scene.turn_offered", "scene.turn",
            ])
        #expect(sceneEvents.map(\.type.rawValue).suffix(2) == ["scene.closed", "scene.performed"])

        // Kill the process. Everything accepted before the kill must still be there afterwards.
        try await service.stop()
        try await service.start()
        try await api.waitUntilHealthy()

        let conversation = try await api.conversationItems(in: conversationID)
        #expect(conversation.filter { $0.authorKind == .person }.count == 2)
        #expect(conversation.filter { $0.authorKind == .character }.count == 4)
        #expect(
            Set(conversation.map(\.text)).isSuperset(of: [
                utterance.text, intent.text, stagedIntent.text, sceneUtterance.text,
                "Servos, I hope!", "It is always heat sinks.",
            ]))

        let afterRestart = try await api.events(after: firstSequence - 1, from: sourceID)
        #expect(afterRestart.map(\.eventID) == [first.eventID, second.eventID, third.eventID])
        #expect(
            afterRestart.compactMap(\.worldSequence) == [
                firstSequence, secondSequence, thirdSequence,
            ])

        // The restarted process resumes a caller that was fully caught up and keeps streaming.
        let caughtUpStream = try await api.openStream(lastEventID: thirdSequence)
        let fourth = try makeEvent(sourceID: sourceID)
        let fourthSequence = try #require(try await api.post(fourth).body.event.worldSequence)
        let fourthDelta = try await caughtUpStream.next(from: sourceID)
        #expect(fourthDelta.event == "delta")
        #expect(fourthDelta.id == String(fourthSequence))
        #expect(fourthDelta.eventID == fourth.eventID)
        #expect(fourthSequence > thirdSequence)
        caughtUpStream.cancel()

        try await service.stop()
    }

    private func makeUtterance(
        in conversationID: ConversationID,
        sourceID: SourceID,
        text: String = "Beaky, are you still there after a restart?"
    ) throws -> PersonUtterance {
        try PersonUtterance(
            conversationID: conversationID,
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: text,
            modality: .typed,
            source: .communicatorComposition,
            sourceID: sourceID,
            occurredAt: Date(),
            confidence: 1
        )
    }

    private func makeIntent(
        in conversationID: ConversationID,
        answering utterance: PersonUtterance,
        text: String = "Still here, April. The world remembers.",
        secondsLater: TimeInterval = 1
    ) throws -> CharacterUtteranceIntent {
        try CharacterUtteranceIntent(
            conversationID: conversationID,
            characterID: utterance.addresseeIDs[0],
            recipientID: utterance.speakerID,
            inResponseToUtteranceID: utterance.utteranceID,
            text: text,
            urgency: 0.4,
            createdAt: utterance.occurredAt.addingTimeInterval(secondsLater)
        )
    }

    private func makeEvent(sourceID: SourceID) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: WorldEventType(validating: "test.blackbox_observed"),
            occurredAt: Date(),
            source: EventSource(id: sourceID, kind: "test"),
            subjectIDs: [],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: ["note": .string("black-box service test")]
        )
    }
}

// MARK: - Child process

/// A class so a failed expectation mid-test cannot leave the child World running: it dies with
/// the handle.
private final class CreatureWorldProcess {
    private let executable: URL
    private let port: Int
    private let mongoURI: String
    private let configURL: URL?
    private var process: Process?

    init(port: Int, mongoURI: String, configURL: URL? = nil) throws {
        let candidate = builtExecutable
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw BlackBoxError.missingExecutable(candidate.path)
        }
        executable = candidate
        self.port = port
        self.mongoURI = mongoURI
        self.configURL = configURL
    }

    func start() async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--host", "127.0.0.1",
            "--port", String(port),
            "--mongodb-uri", mongoURI,
            "--log-level", "warning",
        ]
        // Keep the child from inheriting a configured exporter; the test only needs the service.
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OTEL_EXPORTER_OTLP_ENDPOINT")
        environment.removeValue(forKey: "CREATURE_WORLD_CONFIG")
        if let configURL {
            environment["CREATURE_WORLD_CONFIG"] = configURL.path
        }
        process.environment = environment
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        try process.run()
        self.process = process
    }

    /// SIGTERM is one of the service's graceful-shutdown signals; a clean exit is part of the
    /// contract because open SSE streams must be closed rather than abandoned.
    func stop() async throws {
        guard let process else { return }
        self.process = nil
        process.terminate()
        let deadline = ContinuousClock.now + .seconds(30)
        while process.isRunning {
            guard ContinuousClock.now < deadline else {
                process.interrupt()
                throw BlackBoxError.processDidNotExit
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(process.terminationStatus == 0)
    }

    deinit {
        process?.terminate()
    }
}

/// The built `creature-world` product. SwiftPM keeps `.build/debug` pointing at the active
/// triple's debug directory on macOS and Linux; `CREATURE_WORLD_EXECUTABLE` overrides it for
/// builds that use `--scratch-path` or a release configuration.
private var builtExecutable: URL {
    if let override = ProcessInfo.processInfo.environment["CREATURE_WORLD_EXECUTABLE"] {
        return URL(fileURLWithPath: override)
    }
    return URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CreatureWorldTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // Common
        .appendingPathComponent(".build/debug/creature-world")
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

// MARK: - HTTP client

private struct WorldServiceAPI {
    let client: HTTPClient
    let port: Int

    private var base: String { "http://127.0.0.1:\(port)/world/v1" }

    /// Waits for the socket first with raw connects, then for MongoDB readiness over HTTP.
    /// AsyncHTTPClient's pool backs off after a refused connect and carries that backoff across
    /// requests, so polling it before the port is bound turns a 300 ms startup into 30 s.
    func waitUntilHealthy() async throws {
        let deadline = ContinuousClock.now + .seconds(90)
        while !loopbackPortAccepts(port) {
            guard ContinuousClock.now < deadline else {
                throw BlackBoxError.serviceNeverBecameHealthy
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        while ContinuousClock.now < deadline {
            if let response = try? await client.execute(
                HTTPClientRequest(url: "\(base)/health"),
                timeout: .seconds(2)
            ), response.status == .ok,
                let body = try? await response.body.collect(upTo: 4_096),
                let health = try? WorldJSON.makeDecoder().decode(HealthResponse.self, from: body),
                health.mongodb == "ok"
            {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw BlackBoxError.serviceNeverBecameHealthy
    }

    func post(_ event: WorldEventEnvelope) async throws -> (
        status: HTTPResponseStatus, body: WorldEventAcceptanceResponse
    ) {
        try await postJSON(event, to: "\(base)/events")
    }

    /// Reads every event after `sequence` produced by `sourceID`, following pagination.
    func events(after sequence: Int64, from sourceID: SourceID) async throws
        -> [WorldEventEnvelope]
    {
        var events: [WorldEventEnvelope] = []
        var cursor = sequence
        while true {
            let response = try await client.execute(
                HTTPClientRequest(url: "\(base)/events?after_sequence=\(cursor)&limit=100"),
                timeout: .seconds(15)
            )
            #expect(response.status == .ok)
            let body = try await response.body.collect(upTo: 1_048_576)
            let page = try WorldJSON.makeDecoder().decode(WorldEventPage.self, from: body)
            events += page.events.filter { $0.source.id == sourceID }
            guard page.hasMore, page.nextSequence > cursor else { return events }
            cursor = page.nextSequence
        }
    }

    func post(_ utterance: PersonUtterance) async throws -> (
        status: HTTPResponseStatus, body: UtteranceIngressResult
    ) {
        try await postJSON(
            utterance,
            to: "\(base)/conversations/\(utterance.conversationID.rawValue)/utterances"
        )
    }

    func post(_ intent: CharacterUtteranceIntent) async throws -> (
        status: HTTPResponseStatus, body: CharacterDeliveryResult
    ) {
        try await postJSON(
            intent,
            to: "\(base)/conversations/\(intent.conversationID.rawValue)/responses"
        )
    }

    func stage(_ intent: CharacterUtteranceIntent) async throws -> CharacterStageResult {
        try await postJSON(
            CharacterStageRequest(
                responseID: intent.responseID,
                characterID: intent.characterID,
                recipientID: intent.recipientID
            ),
            to: "\(base)/conversations/\(intent.conversationID.rawValue)/stage"
        ).body
    }

    func post(_ performance: CharacterPerformance) async throws -> (
        status: HTTPResponseStatus, body: CharacterDeliveryResult
    ) {
        try await postJSON(
            performance,
            to: "\(base)/conversations/\(performance.intent.conversationID.rawValue)/performances"
        )
    }

    func login(_ characterID: EntityID, host: String) async throws -> CharacterLoginResult {
        try await postJSON(
            CharacterLoginRequest(
                regionID: try EntityID(validating: "region:home"),
                instance: CharacterMindInstance(host: host, processID: 1, creatureID: "u")),
            to: "\(base)/characters/\(characterID.rawValue)/login"
        ).body
    }

    func scene(_ sceneID: SceneID) async throws -> Scene? {
        let response = try await client.execute(
            HTTPClientRequest(url: "\(base)/scenes/\(sceneID.rawValue)"), timeout: .seconds(15))
        guard response.status == .ok else { return nil }
        let body = try await response.body.collect(upTo: 1_048_576)
        return try WorldJSON.makeDecoder().decode(Scene.self, from: body)
    }

    func submitTurn(to sceneID: SceneID, _ submission: SceneTurnSubmission) async throws -> (
        status: HTTPResponseStatus, body: SceneTurnResult
    ) {
        try await postJSON(submission, to: "\(base)/scenes/\(sceneID.rawValue)/turns")
    }

    func submitTurnStatus(to sceneID: SceneID, _ submission: SceneTurnSubmission) async throws
        -> HTTPResponseStatus
    {
        var request = HTTPClientRequest(url: "\(base)/scenes/\(sceneID.rawValue)/turns")
        request.method = .POST
        request.headers.add(name: "content-type", value: "application/json")
        request.body = .bytes(try WorldJSON.makeEncoder().encode(submission))
        return try await client.execute(request, timeout: .seconds(15)).status
    }

    func conversationItems(in conversationID: ConversationID) async throws
        -> [ConversationItem]
    {
        let response = try await client.execute(
            HTTPClientRequest(
                url: "\(base)/conversations/\(conversationID.rawValue)/items?limit=100"
            ),
            timeout: .seconds(15)
        )
        #expect(response.status == .ok)
        let body = try await response.body.collect(upTo: 1_048_576)
        return try WorldJSON.makeDecoder().decode(ConversationItemPage.self, from: body).items
    }

    func facts(about subjectID: EntityID) async throws -> [Fact] {
        let response = try await client.execute(
            HTTPClientRequest(url: "\(base)/facts?subject_id=\(subjectID.rawValue)&limit=100"),
            timeout: .seconds(15)
        )
        #expect(response.status == .ok)
        let body = try await response.body.collect(upTo: 1_048_576)
        return try WorldJSON.makeDecoder().decode(WorldFactPage.self, from: body).facts
    }

    /// Facts are reduced on the world's own loop after an event is accepted, so a caller who
    /// just caused one waits for it to appear.
    func waitForFact(about subjectID: EntityID, predicate: String) async throws -> Fact {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let fact = try await facts(about: subjectID).first(where: {
                $0.predicate == predicate
            }) {
                return fact
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw BlackBoxError.missingFact(subjectID: subjectID.rawValue, predicate: predicate)
    }

    func openConversationStream(_ conversationID: ConversationID) async throws
        -> ServerSentEventReader
    {
        let response = try await client.execute(
            HTTPClientRequest(
                url: "\(base)/conversations/\(conversationID.rawValue)/stream"
            ),
            deadline: .distantFuture
        )
        #expect(response.status == .ok)
        return ServerSentEventReader(body: response.body)
    }

    private func postJSON<Body: Encodable, Reply: Decodable>(
        _ value: Body,
        to url: String
    ) async throws -> (status: HTTPResponseStatus, body: Reply) {
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "content-type", value: "application/json")
        request.body = .bytes(try WorldJSON.makeEncoder().encode(value))
        let response = try await client.execute(request, timeout: .seconds(15))
        let body = try await response.body.collect(upTo: 1_048_576)
        do {
            return (response.status, try WorldJSON.makeDecoder().decode(Reply.self, from: body))
        } catch {
            throw BlackBoxError.unexpectedReply(
                url: url, status: response.status.code,
                body: String(buffer: body))
        }
    }

    func openStream(lastEventID: Int64?) async throws -> ServerSentEventReader {
        var request = HTTPClientRequest(url: "\(base)/stream")
        if let lastEventID {
            request.headers.add(name: "last-event-id", value: String(lastEventID))
        }
        let response = try await client.execute(request, deadline: .distantFuture)
        #expect(response.status == .ok)
        return ServerSentEventReader(body: response.body)
    }
}

// MARK: - SSE

private struct ServerSentEvent {
    let event: String
    let id: String?
    let data: String

    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try WorldJSON.makeDecoder().decode(type, from: Data(data.utf8))
    }

    /// The world event carried by a replayed `event` frame or a live `delta` frame.
    var envelope: WorldEventEnvelope? {
        switch event {
        case "event": try? decode(WorldEventEnvelope.self)
        case "delta": try? decode(WorldDelta.self).event
        default: nil
        }
    }

    var eventID: EventID? { envelope?.eventID }
}

/// Reads `\n\n`-delimited SSE frames from a streaming body, ignoring keep-alive comments.
private final class ServerSentEventReader: Sendable {
    private let queue = FrameQueue()
    private let task: Task<Void, Never>

    init(body: HTTPClientResponse.Body) {
        let queue = self.queue
        task = Task {
            do {
                var pending = ""
                for try await buffer in body {
                    pending += String(buffer: buffer)
                    while let range = pending.range(of: "\n\n") {
                        let frame = String(pending[..<range.lowerBound])
                        pending = String(pending[range.upperBound...])
                        if let event = Self.parse(frame) {
                            await queue.push(event)
                        }
                    }
                }
                await queue.finish(throwing: BlackBoxError.streamEnded)
            } catch {
                await queue.finish(throwing: error)
            }
        }
    }

    /// The next replayed or live world event from `sourceID`, skipping other suites' traffic.
    func next(from sourceID: SourceID) async throws -> ServerSentEvent {
        while true {
            let frame = try await next()
            if frame.envelope?.source.id == sourceID {
                return frame
            }
        }
    }

    func next() async throws -> ServerSentEvent {
        try await withThrowingTaskGroup(of: ServerSentEvent.self) { group in
            group.addTask { try await self.queue.next() }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw BlackBoxError.streamTimedOut
            }
            guard let event = try await group.next() else { throw BlackBoxError.streamEnded }
            group.cancelAll()
            return event
        }
    }

    func cancel() {
        task.cancel()
    }

    private static func parse(_ frame: String) -> ServerSentEvent? {
        var event = "message"
        var id: String?
        var data: [String] = []
        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = line[..<colon]
            var value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
            switch field {
            case "event": event = String(value)
            case "id": id = String(value)
            case "data": data.append(String(value))
            default: break
            }
        }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(event: event, id: id, data: data.joined(separator: "\n"))
    }
}

private actor FrameQueue {
    private var frames: [ServerSentEvent] = []
    private var waiters: [UUID: CheckedContinuation<ServerSentEvent, any Error>] = [:]
    private var failure: (any Error)?

    func push(_ event: ServerSentEvent) {
        if let (id, waiter) = waiters.first {
            waiters.removeValue(forKey: id)
            waiter.resume(returning: event)
        } else {
            frames.append(event)
        }
    }

    func finish(throwing error: any Error) {
        failure = error
        for waiter in waiters.values {
            waiter.resume(throwing: error)
        }
        waiters.removeAll()
    }

    func next() async throws -> ServerSentEvent {
        if !frames.isEmpty {
            return frames.removeFirst()
        }
        if let failure {
            throw failure
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = continuation
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

private enum BlackBoxError: Error {
    case unexpectedReply(url: String, status: UInt, body: String)
    case missingExecutable(String)
    case noFreePort
    case processDidNotExit
    case serviceNeverBecameHealthy
    case streamEnded
    case missingFact(subjectID: String, predicate: String)
    case streamTimedOut
}
