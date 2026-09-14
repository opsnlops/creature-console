import AsyncHTTPClient
import Foundation
import Logging
import Metrics
import NIOCore
import ServiceLifecycle
import WorldCore

/// The house, both ways: Home Assistant state changes become world events (after a startup
/// snapshot of every mapped entity), and the world's `house.scene_requested` events become
/// `scene.turn_on` calls, answered with `house.scene_activated`.
struct HouseService: Service {
    let configuration: HouseConfiguration
    let homeAssistant: HomeAssistantStream
    let delivery: WorldDelivery
    let client: HTTPClient
    let logger: Logger
    let announcer: HouseAnnouncer
    let eventsCounter = Counter(label: "creature_house.events")

    static let reconnectDelay: Duration = .seconds(5)
    static let flushInterval: Duration = .seconds(30)

    init(
        configuration: HouseConfiguration, token: String, client: HTTPClient, logger: Logger
    ) {
        self.configuration = configuration
        self.homeAssistant = HomeAssistantStream(
            baseURL: configuration.homeAssistantURL, token: token, logger: logger)
        self.delivery = WorldDelivery(
            worldURL: configuration.worldURL, client: client,
            outboxPath: configuration.outboxPath, logger: logger)
        self.client = client
        self.logger = logger
        self.announcer = HouseAnnouncer(
            translator: HouseTranslator(mappings: configuration.mappings))
    }

    func run() async throws {
        // A stop must cut the Home Assistant socket and the world stream, not merely note it:
        // otherwise the service never returns and every upgrade waits for systemd's kill.
        do {
            try await cancelWhenGracefulShutdown {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await followHomeAssistant() }
                    group.addTask { try await followWorld() }
                    group.addTask { try await flushOutbox() }
                    try await group.next()
                    group.cancelAll()
                }
            }
        } catch is CancellationError {
            logger.info("The house is going quiet")
        }
        // Whatever the world could not take yet is on disk already; one last try.
        await delivery.flush()
        try? await client.shutdown()
    }

    // MARK: - House → World

    private func followHomeAssistant() async throws {
        var snapshotTaken = false
        while !Task.isCancelled {
            do {
                if !snapshotTaken {
                    try await snapshot()
                    snapshotTaken = true
                }
                try await homeAssistant.follow { old, new in
                    await self.announce(from: old, to: new)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.warning(
                    "Lost Home Assistant; reconnecting",
                    metadata: ["error": "\(error)", "delay": "\(Self.reconnectDelay)"])
            }
            try await Task.sleep(for: Self.reconnectDelay)
        }
    }

    /// What the house looks like right now, once, so the world starts from the present.
    private func snapshot() async throws {
        let states = try await homeAssistant.states(
            of: configuration.mappings.map(\.entityID), client: client)
        logger.info(
            "Snapshot of the house", metadata: ["entities": "\(states.count)"])
        for state in states {
            await announce(from: nil, to: state)
        }
        // Which places the cameras watch: nothing seen there is a fact, not a shrug.
        var watched: [EntityID] = []
        for mapping in configuration.mappings where mapping.kind == .detection {
            if !watched.contains(mapping.subjectID) { watched.append(mapping.subjectID) }
        }
        for place in watched {
            await delivery.deliver(try Self.cameraWatching(place))
        }
        if configuration.offersScenes {
            let scenes = try await homeAssistant.scenes(client: client)
            logger.info("The house offers scenes", metadata: ["count": "\(scenes.count)"])
            await delivery.deliver(try Self.scenesOffered(scenes, house: configuration.houseID))
        }
    }

    private func announce(from old: EntityState?, to new: EntityState) async {
        do {
            for event in try await announcer.events(from: old, to: new) {
                eventsCounter.increment()
                logger.info(
                    "The house says",
                    metadata: [
                        "world.event_type": "\(event.type.rawValue)",
                        "entity_id": "\(new.entityID)", "state": "\(new.state)",
                    ])
                await delivery.deliver(event)
            }
        } catch {
            logger.error(
                "Could not translate a state change",
                metadata: ["entity_id": "\(new.entityID)", "error": "\(error)"])
        }
    }

    private func flushOutbox() async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: Self.flushInterval)
            if await delivery.pendingCount > 0 {
                await delivery.flush()
            }
        }
    }

    static func cameraWatching(_ place: EntityID) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: HouseEvents.cameraWatching,
            occurredAt: Date(),
            source: EventSource(
                id: try SourceID(validating: "home-assistant:cameras"),
                kind: HouseEvents.sourceKind,
                // The same camera on every restart is the same announcement.
                sourceEventID: "watching:\(place.rawValue)"),
            subjectIDs: [place],
            placeID: place,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: ["place_id": .string(place.rawValue)]
        )
    }

    static func scenesOffered(_ scenes: [HomeAssistantStream.Scene], house: EntityID) throws
        -> WorldEventEnvelope
    {
        let names = scenes.map(\.name)
        return try WorldEventEnvelope(
            type: HouseEvents.scenesOffered,
            occurredAt: Date(),
            source: EventSource(
                id: try SourceID(validating: "home-assistant:scenes"), kind: HouseEvents.sourceKind,
                // The same list is the same announcement; a restart does not repeat it.
                sourceEventID: "scenes:" + names.joined(separator: "|")),
            subjectIDs: [house],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: ["scenes": .array(names.map { .string($0) })]
        )
    }

    // MARK: - World → House

    /// Follow the world's stream for scene requests and act on them.
    private func followWorld() async throws {
        guard configuration.offersScenes else { return }
        var resumeAfter: Int64? = nil
        while !Task.isCancelled {
            do {
                try await followWorldStream(resumeAfter: &resumeAfter)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.warning(
                    "Lost the world's stream; reconnecting",
                    metadata: ["error": "\(error)", "delay": "\(Self.reconnectDelay)"])
            }
            try await Task.sleep(for: Self.reconnectDelay)
        }
    }

    private func followWorldStream(resumeAfter: inout Int64?) async throws {
        var request = HTTPClientRequest(
            url: configuration.worldURL.appendingPathComponent("stream").absoluteString)
        if let resumeAfter {
            request.headers.add(name: "last-event-id", value: String(resumeAfter))
        }
        let response = try await client.execute(request, deadline: .distantFuture)
        guard response.status == .ok else {
            throw WorldDeliveryError.refused(UInt(response.status.code), "stream")
        }
        var parser = ServerSentEventParser()
        for try await buffer in response.body {
            for frame in parser.feed(String(buffer: buffer)) {
                if let id = frame.id.flatMap(Int64.init) { resumeAfter = id }
                guard frame.event == "event" || frame.event == "delta" else { continue }
                let envelope: WorldEventEnvelope
                do {
                    let decoder = WorldJSON.makeDecoder()
                    if frame.event == "delta" {
                        envelope = try decoder.decode(WorldDelta.self, from: Data(frame.data.utf8))
                            .event
                    } else {
                        envelope = try decoder.decode(
                            WorldEventEnvelope.self, from: Data(frame.data.utf8))
                    }
                } catch {
                    logger.debug(
                        "Skipping a frame the house cannot read", metadata: ["error": "\(error)"])
                    continue
                }
                guard envelope.type == HouseEvents.sceneRequested else { continue }
                await act(on: envelope)
            }
        }
        throw HomeAssistantError.streamEnded
    }

    /// `house.scene_requested` → `scene.turn_on` → `house.scene_activated`.
    private func act(on request: WorldEventEnvelope) async {
        guard case .string(let name)? = request.payload["scene"] else { return }
        do {
            let scenes = try await homeAssistant.scenes(client: client)
            guard
                let scene = scenes.first(where: {
                    $0.name.caseInsensitiveCompare(name) == .orderedSame
                })
            else {
                logger.warning("No such scene", metadata: ["house.scene": "\(name)"])
                return
            }
            try await homeAssistant.activate(scene, client: client)
            logger.info("Set the scene", metadata: ["house.scene": "\(scene.name)"])
            await delivery.deliver(
                try WorldEventEnvelope(
                    type: HouseEvents.sceneActivated,
                    occurredAt: Date(),
                    source: EventSource(
                        id: try SourceID(validating: "home-assistant:scenes"),
                        kind: HouseEvents.sourceKind,
                        sourceEventID: "activated:\(request.eventID.rawValue)"),
                    subjectIDs: [configuration.houseID],
                    epistemic: EpistemicState(type: .observed, confidence: 1),
                    payload: ["scene": .string(scene.name), "entity_id": .string(scene.entityID)],
                    causedBy: [.event(request.eventID)],
                    trace: request.trace
                ))
        } catch {
            logger.error(
                "Could not set the scene",
                metadata: ["house.scene": "\(name)", "error": "\(error)"])
        }
    }
}

/// The translator, plus a memory of what the world was last told per entity. A measurement's
/// `minimum_change` is measured from there, not from Home Assistant's previous reading: a
/// thermometer creeping 0.2° at a time would otherwise never be news at all.
actor HouseAnnouncer {
    private let translator: HouseTranslator
    private var announced: [String: EntityState] = [:]

    init(translator: HouseTranslator) {
        self.translator = translator
    }

    func events(from old: EntityState?, to new: EntityState) throws -> [WorldEventEnvelope] {
        let since = announced[new.entityID] ?? old
        let events = try translator.events(from: since, to: new)
        // Remember what the world heard: the snapshot always, and any change that was news.
        if since == nil || !events.isEmpty {
            announced[new.entityID] = new
        }
        return events
    }
}
