import AsyncHTTPClient
import Foundation
import Logging
import Metrics
import NIOCore
import WorldCore

/// One thing the world offered this character to think about.
struct WorldConsideration: Sendable {
    let worldSequence: Int64
    let envelope: WorldEventEnvelope
    let percept: PersonUtterancePercept
}

/// The world offering this character the floor in a scene.
struct WorldSceneConsideration: Sendable {
    let worldSequence: Int64
    let envelope: WorldEventEnvelope
    let offer: SceneTurnOffer
}

enum WorldPerceptSubscriberError: Error, Equatable {
    case invalidURL
    case unexpectedStatus(UInt)
    case streamEnded
    case frameTooLarge
    case connectTimedOut
}

/// Follows Creature World's ordered event stream and hands this character's percepts to the
/// mind, one at a time, in world order.
///
/// The durable cursor decides where to resume. With no cursor the subscription starts at the
/// snapshot's latest sequence — Beaky does not wake up and answer three days of backlog. With a
/// cursor, `Last-Event-ID` replays everything missed and then continues live. A
/// `resnapshot_required` frame, a dropped connection, or a handler failure all lead to the same
/// place: reconnect from the cursor, which the handler advances only after a decision is durable.
actor WorldPerceptSubscriber {
    static let maximumFrameBytes = 1_048_576
    /// How long to wait for the stream's response headers. The body itself has no deadline.
    static let connectTimeout: Duration = .seconds(10)

    private let streamURL: URL
    private let characterID: EntityID
    private let cursor: any WorldCursorStore
    private let logger: Logger
    private let reconnectDelay: Duration
    private let receivedCounter = Counter(label: "creature_agent.world.events.received")
    private let perceptCounter = Counter(label: "creature_agent.world.percepts.received")
    private let reconnectCounter = Counter(label: "creature_agent.world.reconnects")

    init(
        worldURL: URL,
        characterID: EntityID,
        cursor: any WorldCursorStore,
        logger: Logger,
        reconnectDelay: Duration = .seconds(2)
    ) {
        self.streamURL = worldURL.appending(path: "stream")
        self.characterID = characterID
        self.cursor = cursor
        self.logger = logger
        self.reconnectDelay = reconnectDelay
    }

    /// What the mind does with each thing the world offers it. Each must make its decision
    /// durable before returning; the cursor is advanced past the event only after it does.
    struct Handlers: Sendable {
        let utterance: @Sendable (WorldConsideration) async throws -> Void
        let sceneOffer: @Sendable (WorldSceneConsideration) async throws -> Void

        init(
            utterance: @escaping @Sendable (WorldConsideration) async throws -> Void,
            sceneOffer: @escaping @Sendable (WorldSceneConsideration) async throws -> Void = {
                _ in
            }
        ) {
            self.utterance = utterance
            self.sceneOffer = sceneOffer
        }
    }

    /// Runs until cancelled.
    func run(handle: @escaping @Sendable (WorldConsideration) async throws -> Void) async throws {
        try await run(handlers: Handlers(utterance: handle))
    }

    func run(handlers: Handlers) async throws {
        var attempt = 0
        while !Task.isCancelled {
            let resumeAfter = await cursor.current()
            do {
                if attempt > 0 {
                    reconnectCounter.increment()
                }
                try await consume(resumeAfter: resumeAfter, handlers: handlers)
                logger.info("World stream ended; reconnecting from the cursor")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.warning(
                    "World stream interrupted; reconnecting from the cursor",
                    metadata: [
                        "error": "\(error)",
                        "world.cursor": "\(resumeAfter.map(String.init) ?? "none")",
                    ]
                )
            }
            attempt += 1
            try await Task.sleep(for: reconnectDelay)
        }
    }

    private func consume(
        resumeAfter: Int64?,
        handlers: Handlers
    ) async throws {
        var request = HTTPClientRequest(url: streamURL.absoluteString)
        if let resumeAfter {
            request.headers.add(name: "last-event-id", value: String(resumeAfter))
        }
        // A fresh client per connection: AsyncHTTPClient's pool keeps backing off across
        // requests after a refused connect, which would turn a World restart into a hang.
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton, backgroundActivityLogger: logger)
        defer { Task { try? await client.shutdown() } }
        let streamRequest = request
        let logger = self.logger
        let response = try await withTimeout(Self.connectTimeout) {
            try await client.execute(streamRequest, deadline: .distantFuture, logger: logger)
        }
        guard response.status == .ok else {
            throw WorldPerceptSubscriberError.unexpectedStatus(UInt(response.status.code))
        }
        logger.info(
            "Following the world",
            metadata: [
                "world.stream": "\(streamURL.absoluteString)",
                "world.cursor": "\(resumeAfter.map(String.init) ?? "snapshot")",
            ]
        )

        var parser = ServerSentEventParser()
        var pendingBytes = 0
        for try await buffer in response.body {
            pendingBytes += buffer.readableBytes
            let frames = parser.feed(String(buffer: buffer))
            if !frames.isEmpty {
                pendingBytes = 0
            }
            guard pendingBytes <= Self.maximumFrameBytes else {
                throw WorldPerceptSubscriberError.frameTooLarge
            }
            for frame in frames {
                try await process(frame, handlers: handlers)
            }
        }
        throw WorldPerceptSubscriberError.streamEnded
    }

    private func process(
        _ frame: ServerSentEvent,
        handlers: Handlers
    ) async throws {
        switch frame.event {
        case "snapshot":
            // Starting from now: everything before the snapshot is history Beaky did not live.
            if let latest = frame.id.flatMap(Int64.init) {
                try await cursor.advance(to: latest)
                logger.info("Starting from the present", metadata: ["world.sequence": "\(latest)"])
            }
        case "event", "delta":
            let envelope: WorldEventEnvelope
            if frame.event == "delta" {
                envelope = try WorldJSON.makeDecoder()
                    .decode(WorldDelta.self, from: Data(frame.data.utf8)).event
            } else {
                envelope = try WorldJSON.makeDecoder()
                    .decode(WorldEventEnvelope.self, from: Data(frame.data.utf8))
            }
            receivedCounter.increment()
            guard let sequence = envelope.worldSequence else { return }
            if envelope.type == PersonUtterancePercept.eventType {
                let percept = try envelope.decodePayload(as: PersonUtterancePercept.self)
                if percept.characterID == characterID {
                    perceptCounter.increment()
                    try await handlers.utterance(
                        WorldConsideration(
                            worldSequence: sequence,
                            envelope: envelope,
                            percept: percept
                        )
                    )
                }
            } else if envelope.type == SceneTurnOffer.eventType {
                let offer = try envelope.decodePayload(as: SceneTurnOffer.self)
                if offer.characterID == characterID {
                    perceptCounter.increment()
                    try await handlers.sceneOffer(
                        WorldSceneConsideration(
                            worldSequence: sequence,
                            envelope: envelope,
                            offer: offer
                        )
                    )
                }
            }
            try await cursor.advance(to: sequence)
        case "resnapshot_required":
            // The world could not keep our subscription; the cursor already knows where we were.
            throw WorldPerceptSubscriberError.streamEnded
        default:
            break
        }
    }
}

private func withTimeout<Value: Sendable>(
    _ timeout: Duration,
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw WorldPerceptSubscriberError.connectTimedOut
        }
        guard let value = try await group.next() else {
            throw WorldPerceptSubscriberError.connectTimedOut
        }
        group.cancelAll()
        return value
    }
}
