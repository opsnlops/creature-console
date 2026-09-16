import AsyncHTTPClient
import Common
import Foundation
import Logging
import NIOCore
import ServiceLifecycle
import WorldCore

/// Follows Creature Server's websocket and tells the world what each bird's sensors say.
struct BodyService: Service {
    let configuration: BodyConfiguration
    let server: CreatureServerClient
    let client: HTTPClient
    let logger: Logger

    func run() async throws {
        let names = await creatureNames()
        logger.info(
            "creature-body \(CreatureBodyBuildInfo.version)",
            metadata: [
                "creature_server": "\(server.serverHostname):\(server.serverPort)",
                "world.url": "\(configuration.worldURL)",
                "creatures": "\(names.count)",
            ])
        let world = WorldGate(url: configuration.worldURL, client: client, logger: logger)
        await world.seedGlossary(BodyFacts.meanings)
        let processor = BodyProcessor(
            configuration: configuration, names: names, world: world, logger: logger)
        await server.connectWebsocket(processor: processor)
        logger.info("Listening to the birds' bodies")
        try await gracefulShutdown()
        _ = await server.disconnectWebsocket()
    }

    private func creatureNames() async -> [CreatureIdentifier: String] {
        switch await server.getAllCreatures() {
        case .success(let creatures):
            return Dictionary(uniqueKeysWithValues: creatures.map { ($0.id, $0.name) })
        case .failure(let error):
            logger.warning(
                "Could not list the creatures; names will be looked up as they report",
                metadata: ["error": "\(error)"])
            return [:]
        }
    }
}

/// The world's door: facts go in as `facts.given`, a batch at a time; meanings are seeded
/// once. A world that is down loses a few seconds of readings, which come again.
actor WorldGate {
    private let url: URL
    private let client: HTTPClient
    private let logger: Logger
    private(set) var cast = 0

    init(url: URL, client: HTTPClient, logger: Logger) {
        self.url = url
        self.client = client
        self.logger = logger
    }

    func seedGlossary(_ meanings: [String: String]) async {
        for (predicate, meaning) in meanings.sorted(by: { $0.key < $1.key }) {
            var request = HTTPClientRequest(
                url: url.appendingPathComponent("fact-kinds/\(predicate)").absoluteString)
            request.method = .PUT
            request.headers.add(name: "content-type", value: "application/json")
            let body: [String: WorldJSONValue] = [
                "meaning": .string(meaning), "audience": .string("minds"),
                "updated_by": .string("body:sensors"),
            ]
            request.body = .bytes(try! WorldJSON.makeEncoder().encode(body))
            do {
                // Only a kind the world does not have yet: a Wizard's rewording is never touched.
                var probe = HTTPClientRequest(
                    url: url.appendingPathComponent("fact-kinds").absoluteString)
                probe.method = .GET
                let page = try await client.execute(probe, timeout: .seconds(10))
                let known = String(buffer: try await page.body.collect(upTo: 1 << 20))
                if known.contains("\"\(predicate)\"") { continue }
                let response = try await client.execute(request, timeout: .seconds(10))
                guard response.status == .ok || response.status == .created else {
                    logger.warning(
                        "The world would not take a meaning",
                        metadata: [
                            "predicate": "\(predicate)", "status": "\(response.status.code)",
                        ])
                    continue
                }
                logger.info("Taught the world a word", metadata: ["predicate": "\(predicate)"])
            } catch {
                logger.warning(
                    "Could not seed the glossary", metadata: ["error": "\(error)"])
                return
            }
        }
    }

    func deliver(_ events: [WorldEventEnvelope]) async {
        guard !events.isEmpty else { return }
        do {
            var request = HTTPClientRequest(
                url: url.appendingPathComponent("events:batch").absoluteString)
            request.method = .POST
            request.headers.add(name: "content-type", value: "application/json")
            request.body = .bytes(try WorldJSON.makeEncoder().encode(["events": events]))
            let response = try await client.execute(request, timeout: .seconds(15))
            guard response.status == .accepted || response.status == .ok else {
                let body = try await response.body.collect(upTo: 4_096)
                logger.warning(
                    "The world refused a batch",
                    metadata: [
                        "status": "\(response.status.code)", "body": "\(String(buffer: body))",
                    ])
                return
            }
            cast += events.count
        } catch {
            logger.warning(
                "Could not reach the world; the next readings will", metadata: ["error": "\(error)"]
            )
        }
    }
}

/// Every message from the server; only the sensor reports matter here.
struct BodyProcessor: MessageProcessor {
    private let state: BodyState

    init(
        configuration: BodyConfiguration, names: [CreatureIdentifier: String], world: WorldGate,
        logger: Logger
    ) {
        state = BodyState(configuration: configuration, names: names, world: world, logger: logger)
    }

    func processBoardSensorReport(_ report: BoardSensorReport) async {
        await state.take(creatureID: report.creatureId, facts: BodyFacts.facts(from: report))
    }

    func processMotorSensorReport(_ report: MotorSensorReport) async {
        await state.take(creatureID: report.creatureId, facts: BodyFacts.facts(from: report))
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) async {}
    func processEmergencyStop(_ emergencyStop: EmergencyStop) async {}
    func processLog(_ logItem: ServerLogItem) async {}
    func processDynamixelSensorReport(_ report: DynamixelSensorReport) async {
        await state.take(
            creatureID: report.creatureId, name: report.creatureName,
            facts: BodyFacts.facts(from: report))
    }
    func processNotice(_ notice: Notice) async {}
    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) async {}
    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) async {}
    func processSystemCounters(_ payload: ServerCountersPayload) async {
        await state.takeServer(payload)
    }
    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) async {}
    func processJobProgress(_ jobProgress: JobProgress) async {}
    func processJobComplete(_ jobComplete: JobCompletion) async {}
    func processIdleStateChanged(_ idleState: IdleStateChanged) async {}
    func processCreatureActivity(_ activity: CreatureActivity) async {}
}

/// The change detector and the names, behind an actor so reports from the socket queue up.
actor BodyState {
    private let configuration: BodyConfiguration
    private var names: [CreatureIdentifier: String]
    private let world: WorldGate
    private let logger: Logger
    private var ledger = BodyLedger()
    private var unknown: Set<CreatureIdentifier> = []
    private var lastCounters: (counters: SystemCountersDTO, at: Date)?

    init(
        configuration: BodyConfiguration, names: [CreatureIdentifier: String], world: WorldGate,
        logger: Logger
    ) {
        self.configuration = configuration
        self.names = names
        self.world = world
        self.logger = logger
    }

    /// The server's counters: its own vital signs, and each bird's runtime state.
    func takeServer(_ payload: ServerCountersPayload, now: Date = Date()) async {
        let serverFacts = BodyFacts.facts(from: payload.counters, previous: lastCounters, now: now)
        lastCounters = (payload.counters, now)
        await say(
            serverFacts, about: BodyFacts.serverID, now: now,
            interval: TimeInterval(configuration.serverIntervalSeconds))
        for state in payload.runtimeStates {
            guard let runtime = state.runtime else { continue }
            await take(
                creatureID: state.creatureId, facts: BodyFacts.facts(from: runtime), now: now)
        }
    }

    func take(
        creatureID: CreatureIdentifier, name reported: String? = nil,
        facts: [String: WorldJSONValue], now: Date = Date()
    ) async {
        // A Dynamixel report names its creature; remember it in case the server's list did not.
        if let reported, !reported.isEmpty, names[creatureID] == nil {
            names[creatureID] = reported
        }
        guard let name = names[creatureID], let subject = configuration.character(named: name)
        else {
            if unknown.insert(creatureID).inserted {
                logger.warning(
                    "A creature the server never named is reporting; ignoring it",
                    metadata: ["creature_id": "\(creatureID)"])
            }
            return
        }
        await say(
            facts, about: subject, now: now,
            interval: TimeInterval(configuration.minimumIntervalSeconds))
    }

    private func say(
        _ facts: [String: WorldJSONValue], about subject: EntityID, now: Date,
        interval: TimeInterval
    ) async {
        let changes = ledger.changes(
            for: subject, facts: facts, now: now, thresholds: configuration.thresholds,
            minimumInterval: interval, validFor: TimeInterval(configuration.validForSeconds))
        guard !changes.isEmpty else { return }
        do {
            let events = try changes.map {
                try BodyFacts.given(
                    subject: subject, predicate: $0.predicate, value: $0.value,
                    validFor: configuration.validForSeconds, at: now)
            }
            await world.deliver(events)
            logger.debug(
                "Told the world",
                metadata: [
                    "subject": "\(subject.rawValue)",
                    "facts": "\(changes.map(\.predicate).joined(separator: ", "))",
                ])
        } catch {
            logger.error("Could not make a fact", metadata: ["error": "\(error)"])
        }
    }
}
