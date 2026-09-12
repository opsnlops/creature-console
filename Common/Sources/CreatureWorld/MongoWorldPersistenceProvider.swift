import AsyncHTTPClient
import Foundation
import Logging
import Observability
import ServiceLifecycle
import WorldCore

struct MongoWorldPersistenceConnection: Sendable {
    let acceptEvent: @Sendable (WorldEventEnvelope) async throws -> WorldEventAcceptance
    let events: @Sendable (Int64, Int) async throws -> WorldEventPage
    let currentFacts: @Sendable (EntityID?, FactID?, Int) async throws -> WorldFactPage
    let timers: @Sendable (WorldTimerStatus?, TimerID?, Int) async throws -> WorldTimerPage
    let snapshot: @Sendable (Int) async throws -> WorldSnapshot
    let subscribe: @Sendable () async throws -> WorldDeltaStream
    let finishSubscriptions: @Sendable () async -> Void
    let isHealthy: @Sendable () async -> Bool
    let recoverTimers: @Sendable () async throws -> Void
    let scheduleTimer: @Sendable (WorldTimer) async throws -> Void
    let cancelTimer: @Sendable (TimerID) async throws -> Bool
    let ingestUtterance: @Sendable (PersonUtterance) async throws -> UtteranceIngressResult
    let respondAsCharacter:
        @Sendable (CharacterUtteranceIntent) async throws -> CharacterDeliveryResult
    let stageCharacter:
        @Sendable (CharacterStageRequest, ConversationID) async throws -> CharacterStageResult
    let recordPerformance:
        @Sendable (CharacterPerformance, ConversationID) async throws -> CharacterDeliveryResult
    let conversationItems:
        @Sendable (ConversationID, ConversationItemID?, Int) async throws -> ConversationItemPage
    let deliveries:
        @Sendable (ConversationID, ResponseID?, Int) async throws -> CharacterDeliveryPage
    let loginCharacter:
        @Sendable (EntityID, CharacterLoginRequest) async throws -> CharacterLoginResult
    let heartbeatCharacter:
        @Sendable (EntityID, CharacterSessionReference) async throws -> CharacterSession
    let logoutCharacter:
        @Sendable (EntityID, CharacterSessionReference) async throws -> CharacterSession
    let characterSessions: @Sendable () async throws -> [CharacterSession]
    let submitSceneTurn: @Sendable (SceneTurnSubmission, SceneID) async throws -> SceneTurnResult
    let scene: @Sendable (SceneID) async throws -> Scene?
    let recentScenes: @Sendable (Int) async throws -> [Scene]
    let shutdown: @Sendable () async -> Void

    init(
        persistence: MongoWorldPersistence,
        presence: PresenceConfiguration = PresenceConfiguration(),
        creatureServer: CreatureServerConfiguration? = nil,
        sceneLimits: SceneLimits = SceneLimits(),
        scenePerformance: ScenePerformanceMode = .streaming,
        regions: [EntityID: RegionConfiguration] = [:],
        leadCharacter: EntityID = CreatureWorldConfiguration.defaultLeadCharacter,
        publishConversationItem: @escaping @Sendable (ConversationItem) async -> Void = { _ in },
        clock: any WorldClock = SystemWorldClock(),
        logger: Logger
    ) throws {
        let world = World(
            eventStore: persistence.events,
            factStore: persistence.facts,
            reducers: [],
            clock: clock
        )
        let timerScheduler = WorldTimerScheduler(
            store: persistence.timers,
            eventSink: world,
            clock: clock,
            logger: logger
        )
        let deliveryRouter = try CharacterDeliveryRouter(
            presenceProvider: AssumedPresenceProvider(configuration: presence, clock: clock),
            repository: persistence.characterDeliveries,
            physicalSpeechSink: NotConnectedPhysicalSpeechSink(logger: logger),
            communicatorSink: CommunicatorDeliverySink(),
            clock: clock
        )
        let sessionService = CharacterSessionService(
            repository: persistence.characterSessions,
            clock: clock,
            announce: { _ = try await world.accept($0) }
        )
        // Scenes are performed through Creature Server's dialog pipeline when one is configured;
        // the characters speak through the creatures their minds logged in with.
        let performer: any ScenePerforming
        let sceneClient: HTTPClient?
        if let creatureServer {
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            sceneClient = client
            let creatures = SessionCreatureResolver(sessions: sessionService)
            let complete = CreatureServerScenePerformer(
                configuration: creatureServer,
                creatures: creatures,
                client: client,
                clock: clock,
                logger: logger
            )
            switch scenePerformance {
            case .streaming:
                performer = StreamingScenePerformer(
                    configuration: creatureServer,
                    regions: regions,
                    creatures: creatures,
                    fallback: complete,
                    client: client,
                    clock: clock,
                    logger: logger
                )
            case .complete:
                performer = complete
            }
        } else {
            sceneClient = nil
            performer = NotConnectedScenePerformer(clock: clock)
        }
        let conversations = persistence.conversations
        let sceneService = SceneService(
            repository: persistence.scenes,
            clock: clock,
            limits: sceneLimits,
            performer: performer,
            announce: { _ = try await world.accept($0) },
            scheduleDeadline: { try await timerScheduler.schedule($0) },
            recordTurn: { scene, turn in
                // A spoken turn is a conversation item like any other, so the Communicator and
                // history show the exchange as it is composed.
                let item = try ConversationItem(
                    conversationID: scene.conversationID,
                    authorID: turn.characterID,
                    authorKind: .character,
                    text: turn.text ?? "",
                    createdAt: turn.answeredAt,
                    responseID: turn.responseID,
                    trace: scene.trace
                )
                try await conversations.saveConversationItem(item)
                await publishConversationItem(item)
                return item.itemID
            }
        )
        let conversationIngress = PersonUtteranceIngressService(
            repository: persistence.conversations,
            sink: WorldPersonUtterancePerceptSink(
                world: world, sessions: sessionService, scenes: sceneService),
            scenePlanner: PresentCharactersScenePlanner(sessions: sessionService),
            addresseeResolver: PresentCharactersAddresseeResolver(
                sessions: sessionService, rule: LeadAddresseeRule(lead: leadCharacter))
        )
        // Floor deadlines fire as world timers; the scene service hears them from the stream.
        let floorWatcher = Task {
            do {
                for try await delta in try await world.subscribe() {
                    guard delta.event.type == SceneService.floorExpiredEventType,
                        case .string(let rawScene)? = delta.event.payload["scene_id"],
                        case .string(let rawResponse)? = delta.event.payload["response_id"],
                        let sceneID = SceneID(rawValue: rawScene),
                        let responseID = ResponseID(rawValue: rawResponse)
                    else { continue }
                    try await sceneService.floorExpired(sceneID: sceneID, responseID: responseID)
                }
            } catch {
                logger.warning(
                    "Stopped watching for scene floor deadlines", metadata: ["error": "\(error)"])
            }
        }
        acceptEvent = { try await world.accept($0) }
        events = { sequence, limit in
            let loaded = try await persistence.events.events(
                after: sequence,
                limit: limit + 1
            )
            let hasMore = loaded.count > limit
            let pageEvents = Array(loaded.prefix(limit))
            return WorldEventPage(
                events: pageEvents,
                nextSequence: pageEvents.last?.worldSequence ?? sequence,
                hasMore: hasMore
            )
        }
        currentFacts = { subjectID, after, limit in
            let loaded = try await persistence.facts.currentFacts(
                subjectID: subjectID,
                after: after,
                limit: limit + 1
            )
            let hasMore = loaded.count > limit
            let pageFacts = Array(loaded.prefix(limit))
            return WorldFactPage(
                facts: pageFacts,
                nextFactID: pageFacts.last?.factID,
                hasMore: hasMore
            )
        }
        timers = { status, after, limit in
            let loaded = try await persistence.timers.timers(
                status: status,
                after: after,
                limit: limit + 1
            )
            let hasMore = loaded.count > limit
            let pageTimers = Array(loaded.prefix(limit))
            return WorldTimerPage(
                timers: pageTimers,
                nextTimerID: pageTimers.last?.timerID,
                hasMore: hasMore
            )
        }
        snapshot = { limit in
            let latestSequence = try await persistence.events.latestSequence()
            let loadedFacts = try await persistence.facts.currentFacts(
                subjectID: nil,
                after: nil,
                limit: limit + 1
            )
            let loadedTimers = try await persistence.timers.timers(limit: limit + 1)
            return WorldSnapshot(
                latestSequence: latestSequence,
                facts: Array(loadedFacts.prefix(limit)),
                timers: Array(loadedTimers.prefix(limit)),
                factsTruncated: loadedFacts.count > limit,
                timersTruncated: loadedTimers.count > limit
            )
        }
        subscribe = { try await world.subscribe() }
        finishSubscriptions = { await world.finishSubscriptions() }
        isHealthy = { await persistence.isHealthy() }
        recoverTimers = { try await timerScheduler.recover() }
        scheduleTimer = { try await timerScheduler.schedule($0) }
        cancelTimer = { try await timerScheduler.cancel(timerID: $0) }
        ingestUtterance = {
            try await conversationIngress.ingest(
                $0,
                context: UtteranceIngressContext(boundary: .trustedLAN)
            )
        }
        respondAsCharacter = { try await deliveryRouter.route($0) }
        // A mind must hold the character's live session to perform as it, once anyone does.
        stageCharacter = { request, conversationID in
            try await sessionService.requireHolder(
                of: request.characterID, sessionID: request.sessionID)
            return try await deliveryRouter.stage(request, in: conversationID)
        }
        recordPerformance = { performance, conversationID in
            try await sessionService.requireHolder(
                of: performance.intent.characterID, sessionID: performance.sessionID)
            return try await deliveryRouter.recordPerformance(performance, in: conversationID)
        }
        loginCharacter = { try await sessionService.login($0, $1) }
        heartbeatCharacter = { try await sessionService.heartbeat($0, $1) }
        logoutCharacter = { try await sessionService.logout($0, $1) }
        characterSessions = { try await sessionService.characterSessions() }
        submitSceneTurn = { submission, sceneID in
            try await sessionService.requireHolder(
                of: submission.characterID, sessionID: submission.sessionID)
            return try await sceneService.submit(submission, to: sceneID)
        }
        scene = { try await sceneService.scene(id: $0) }
        recentScenes = { try await sceneService.recentScenes(limit: $0) }
        conversationItems = { conversationID, after, limit in
            let loaded = try await persistence.conversations.conversationItems(
                in: conversationID,
                after: after,
                limit: limit + 1
            )
            let hasMore = loaded.count > limit
            let pageItems = Array(loaded.prefix(limit))
            return ConversationItemPage(
                items: pageItems,
                nextItemID: pageItems.last?.itemID,
                hasMore: hasMore
            )
        }
        deliveries = { conversationID, after, limit in
            let loaded = try await persistence.characterDeliveries.deliveries(
                in: conversationID,
                after: after,
                limit: limit + 1
            )
            let hasMore = loaded.count > limit
            let page = loaded.prefix(limit).map {
                CharacterDeliveryRecord(
                    intent: $0.intent,
                    decision: $0.decision,
                    outcome: $0.outcome,
                    conversationItem: $0.conversationItem
                )
            }
            return CharacterDeliveryPage(
                deliveries: page,
                nextResponseID: page.last?.intent.responseID,
                hasMore: hasMore
            )
        }
        shutdown = {
            floorWatcher.cancel()
            await world.closeSubscriptions(error: WorldAPIError.databaseUnavailable)
            await timerScheduler.shutdown()
            try? await sceneClient?.shutdown()
            await persistence.cluster.disconnect()
        }
    }

    init(
        acceptEvent: @escaping @Sendable (WorldEventEnvelope) async throws -> WorldEventAcceptance =
            {
                _ in throw WorldAPIError.databaseUnavailable
            },
        events: @escaping @Sendable (Int64, Int) async throws -> WorldEventPage = {
            _, _ in throw WorldAPIError.databaseUnavailable
        },
        currentFacts: @escaping @Sendable (EntityID?, FactID?, Int) async throws -> WorldFactPage =
            {
                _, _, _ in throw WorldAPIError.databaseUnavailable
            },
        timers:
            @escaping @Sendable (WorldTimerStatus?, TimerID?, Int) async throws -> WorldTimerPage =
            {
                _, _, _ in throw WorldAPIError.databaseUnavailable
            },
        snapshot: @escaping @Sendable (Int) async throws -> WorldSnapshot = {
            _ in throw WorldAPIError.databaseUnavailable
        },
        subscribe: @escaping @Sendable () async throws -> WorldDeltaStream = {
            throw WorldAPIError.databaseUnavailable
        },
        finishSubscriptions: @escaping @Sendable () async -> Void = {},
        isHealthy: @escaping @Sendable () async -> Bool,
        recoverTimers: @escaping @Sendable () async throws -> Void = {},
        scheduleTimer: @escaping @Sendable (WorldTimer) async throws -> Void = { _ in },
        cancelTimer: @escaping @Sendable (TimerID) async throws -> Bool = { _ in false },
        ingestUtterance:
            @escaping @Sendable (PersonUtterance) async throws
            -> UtteranceIngressResult = { _ in throw WorldAPIError.databaseUnavailable },
        respondAsCharacter:
            @escaping @Sendable (CharacterUtteranceIntent) async throws
            -> CharacterDeliveryResult = { _ in throw WorldAPIError.databaseUnavailable },
        stageCharacter:
            @escaping @Sendable (CharacterStageRequest, ConversationID) async throws
            -> CharacterStageResult = { _, _ in throw WorldAPIError.databaseUnavailable },
        recordPerformance:
            @escaping @Sendable (CharacterPerformance, ConversationID) async throws
            -> CharacterDeliveryResult = { _, _ in throw WorldAPIError.databaseUnavailable },
        conversationItems:
            @escaping @Sendable (ConversationID, ConversationItemID?, Int) async throws
            -> ConversationItemPage = { _, _, _ in throw WorldAPIError.databaseUnavailable },
        deliveries:
            @escaping @Sendable (ConversationID, ResponseID?, Int) async throws
            -> CharacterDeliveryPage = { _, _, _ in throw WorldAPIError.databaseUnavailable },
        loginCharacter:
            @escaping @Sendable (EntityID, CharacterLoginRequest) async throws
            -> CharacterLoginResult = { _, _ in throw WorldAPIError.databaseUnavailable },
        heartbeatCharacter:
            @escaping @Sendable (EntityID, CharacterSessionReference) async throws
            -> CharacterSession = { _, _ in throw WorldAPIError.databaseUnavailable },
        logoutCharacter:
            @escaping @Sendable (EntityID, CharacterSessionReference) async throws
            -> CharacterSession = { _, _ in throw WorldAPIError.databaseUnavailable },
        characterSessions: @escaping @Sendable () async throws -> [CharacterSession] = {
            throw WorldAPIError.databaseUnavailable
        },
        submitSceneTurn:
            @escaping @Sendable (SceneTurnSubmission, SceneID) async throws -> SceneTurnResult = {
                _, _ in throw WorldAPIError.databaseUnavailable
            },
        scene: @escaping @Sendable (SceneID) async throws -> Scene? = {
            _ in throw WorldAPIError.databaseUnavailable
        },
        recentScenes: @escaping @Sendable (Int) async throws -> [Scene] = {
            _ in throw WorldAPIError.databaseUnavailable
        },
        shutdown: @escaping @Sendable () async -> Void
    ) {
        self.acceptEvent = acceptEvent
        self.events = events
        self.currentFacts = currentFacts
        self.timers = timers
        self.snapshot = snapshot
        self.subscribe = subscribe
        self.finishSubscriptions = finishSubscriptions
        self.isHealthy = isHealthy
        self.recoverTimers = recoverTimers
        self.scheduleTimer = scheduleTimer
        self.cancelTimer = cancelTimer
        self.ingestUtterance = ingestUtterance
        self.respondAsCharacter = respondAsCharacter
        self.stageCharacter = stageCharacter
        self.recordPerformance = recordPerformance
        self.conversationItems = conversationItems
        self.deliveries = deliveries
        self.loginCharacter = loginCharacter
        self.heartbeatCharacter = heartbeatCharacter
        self.logoutCharacter = logoutCharacter
        self.characterSessions = characterSessions
        self.submitSceneTurn = submitSceneTurn
        self.scene = scene
        self.recentScenes = recentScenes
        self.shutdown = shutdown
    }
}

actor MongoWorldPersistenceProvider {
    typealias Connector = @Sendable (String, Logger) async throws -> MongoWorldPersistenceConnection

    private let connector: Connector
    private let logger: Logger
    private let uri: String
    private let conversationUpdates = ConversationUpdateBroker()
    private var consecutiveFailures = 0
    private var isConnecting = false
    private var connection: MongoWorldPersistenceConnection?

    init(
        uri: String,
        presence: PresenceConfiguration = PresenceConfiguration(),
        creatureServer: CreatureServerConfiguration? = nil,
        sceneLimits: SceneLimits = SceneLimits(),
        scenePerformance: ScenePerformanceMode = .streaming,
        regions: [EntityID: RegionConfiguration] = [:],
        leadCharacter: EntityID = CreatureWorldConfiguration.defaultLeadCharacter,
        logger: Logger,
        connector: Connector? = nil
    ) {
        self.uri = uri
        self.logger = logger
        let conversationUpdates = self.conversationUpdates
        self.connector =
            connector ?? { uri, logger in
                let persistence = try await MongoWorldPersistence.connect(to: uri, logger: logger)
                do {
                    return try MongoWorldPersistenceConnection(
                        persistence: persistence,
                        presence: presence,
                        creatureServer: creatureServer,
                        sceneLimits: sceneLimits,
                        scenePerformance: scenePerformance,
                        regions: regions,
                        leadCharacter: leadCharacter,
                        publishConversationItem: { await conversationUpdates.publish($0) },
                        logger: logger
                    )
                } catch {
                    await persistence.cluster.disconnect()
                    throw error
                }
            }
    }

    func connectIfNeeded() async {
        guard connection == nil, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        do {
            let candidate = try await connector(uri, logger)
            do {
                try await candidate.recoverTimers()
            } catch {
                await candidate.shutdown()
                throw error
            }
            connection = candidate
            if consecutiveFailures > 0 {
                logger.info(
                    "MongoDB connection recovered",
                    metadata: ["mongodb.retry_attempts": "\(consecutiveFailures)"]
                )
            }
            consecutiveFailures = 0
        } catch {
            consecutiveFailures += 1
            let metadata: Logger.Metadata = [
                "error": "\(error.localizedDescription)",
                "mongodb.retry_attempt": "\(consecutiveFailures)",
            ]
            if consecutiveFailures == 1 {
                logger.warning(
                    "MongoDB is unavailable; Creature World will continue starting and retry",
                    metadata: metadata
                )
            } else {
                logger.debug("MongoDB retry failed", metadata: metadata)
            }
        }
    }

    func isHealthy() async -> Bool {
        guard let connection else { return false }
        guard await connection.isHealthy() else {
            logger.warning("MongoDB health check failed; persistence is unavailable")
            await connection.shutdown()
            self.connection = nil
            return false
        }
        return true
    }

    func shutdown() async {
        await conversationUpdates.finish()
        await connection?.shutdown()
        connection = nil
    }

    func schedule(_ timer: WorldTimer) async throws {
        guard let connection else { throw MongoWorldPersistenceProviderError.unavailable }
        try await connection.scheduleTimer(timer)
    }

    func cancel(timerID: TimerID) async throws -> Bool {
        guard let connection else { throw MongoWorldPersistenceProviderError.unavailable }
        return try await connection.cancelTimer(timerID)
    }

    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.acceptEvent(event)
    }

    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.events(sequence, limit)
    }

    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int) async throws
        -> WorldFactPage
    {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.currentFacts(subjectID, after, limit)
    }

    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.timers(status, after, limit)
    }

    func snapshot(limit: Int) async throws -> WorldSnapshot {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.snapshot(limit)
    }

    func subscribe() async throws -> WorldDeltaStream {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.subscribe()
    }

    func finishSubscriptions() async {
        await connection?.finishSubscriptions()
    }

    func ingest(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        let result = try await connection.ingestUtterance(utterance)
        if result.disposition == .accepted {
            await conversationUpdates.publish(result.conversationItem)
        }
        return result
    }

    /// Carries one Beaky turn into the shared conversation. The router decides the stage from
    /// fresh presence and persists the canonical item first; the item is then offered to every
    /// live conversation subscriber regardless of route, so a turn performed aloud still appears
    /// in Communicator history. Live publication is at-least-once; clients upsert by item ID.
    func respond(_ intent: CharacterUtteranceIntent) async throws -> CharacterDeliveryResult {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        let result = try await connection.respondAsCharacter(intent)
        if result.disposition == .accepted {
            await conversationUpdates.publish(result.conversationItem)
        }
        return result
    }

    func stage(
        _ request: CharacterStageRequest,
        in conversationID: ConversationID
    ) async throws -> CharacterStageResult {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.stageCharacter(request, conversationID)
    }

    /// Records a turn the mind performed on a stage the world decided; the canonical item is
    /// then offered to every live conversation subscriber, so what Beaky said aloud shows up in
    /// Communicator history exactly like a routed turn.
    func perform(
        _ performance: CharacterPerformance,
        in conversationID: ConversationID
    ) async throws -> CharacterDeliveryResult {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        let result = try await connection.recordPerformance(performance, conversationID)
        if result.disposition == .accepted {
            await conversationUpdates.publish(result.conversationItem)
        }
        return result
    }

    func login(
        _ characterID: EntityID,
        _ request: CharacterLoginRequest
    ) async throws -> CharacterLoginResult {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.loginCharacter(characterID, request)
    }

    func heartbeat(
        _ characterID: EntityID,
        _ reference: CharacterSessionReference
    ) async throws -> CharacterSession {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.heartbeatCharacter(characterID, reference)
    }

    func logout(
        _ characterID: EntityID,
        _ reference: CharacterSessionReference
    ) async throws -> CharacterSession {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.logoutCharacter(characterID, reference)
    }

    func characterSessions() async throws -> [CharacterSession] {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.characterSessions()
    }

    func submitSceneTurn(_ submission: SceneTurnSubmission, to sceneID: SceneID) async throws
        -> SceneTurnResult
    {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.submitSceneTurn(submission, sceneID)
    }

    func scene(id: SceneID) async throws -> Scene? {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.scene(id)
    }

    func recentScenes(limit: Int) async throws -> [Scene] {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.recentScenes(limit)
    }

    func conversationItems(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.conversationItems(conversationID, itemID, limit)
    }

    func deliveries(
        in conversationID: ConversationID,
        after responseID: ResponseID?,
        limit: Int
    ) async throws -> CharacterDeliveryPage {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.deliveries(conversationID, responseID, limit)
    }

    func subscribe(to conversationID: ConversationID) async throws -> ConversationItemStream {
        try await conversationUpdates.subscribe(to: conversationID)
    }

    func finishConversationSubscriptions() async {
        await conversationUpdates.finish()
    }
}

extension MongoWorldPersistenceProvider: ConversationApplicationService {}
extension MongoWorldPersistenceProvider: CharacterSessionApplicationService {}
extension MongoWorldPersistenceProvider: SceneApplicationService {}

/// Which creature a character speaks through: the one its mind logged in with.
private struct SessionCreatureResolver: CharacterCreatureResolving {
    let sessions: CharacterSessionService

    func creatureID(for characterID: EntityID) async throws -> String? {
        try await sessions.liveSession(for: characterID)?.instance.creatureID
    }
}

/// April's words go to the character she names if that character is logged in; otherwise to
/// the lead. Names are the part after `character:`.
private struct PresentCharactersAddresseeResolver: AddresseeResolving {
    let sessions: CharacterSessionService
    let rule: LeadAddresseeRule

    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> EntityID {
        let now = Date()
        let present = try await sessions.characterSessions().filter { $0.isLive(at: now) }
        var names: [String: EntityID] = [:]
        for session in present {
            let raw = session.characterID.rawValue
            if let colon = raw.firstIndex(of: ":") {
                names[String(raw[raw.index(after: colon)...]).lowercased()] = session.characterID
            }
        }
        return rule.addressee(in: utterance.text, present: names)
    }
}

/// More than one character logged into the addressee's region means a scene: the world will
/// hand out the floor, and the addressee must not answer on its own.
private struct PresentCharactersScenePlanner: ScenePlanning {
    let sessions: CharacterSessionService

    func planScene(for utterance: PersonUtterance, addressee: EntityID) async throws -> SceneID? {
        guard let session = try await sessions.liveSession(for: addressee) else { return nil }
        let present = try await sessions.present(in: session.regionID)
        return present.count > 1 ? .generated() : nil
    }
}

private struct WorldPersonUtterancePerceptSink: PersonUtterancePerceptSink {
    let world: World
    let sessions: CharacterSessionService
    let scenes: SceneService

    func submit(_ percept: PersonUtterancePercept) async throws -> UtterancePerceptAcceptance {
        let utterance = percept.utterance
        var sceneToOpen: (region: EntityID, participants: [EntityID])?
        if percept.sceneID != nil,
            let addressee = try await sessions.liveSession(for: percept.characterID)
        {
            let present = try await sessions.present(in: addressee.regionID).map(\.characterID)
            sceneToOpen = (addressee.regionID, present)
        }
        let envelope = try WorldEventEnvelope(
            occurredAt: utterance.occurredAt,
            observedAt: utterance.receivedAt,
            source: EventSource(
                id: utterance.sourceID,
                kind: utterance.source.rawValue,
                sourceEventID: utterance.utteranceID.rawValue
            ),
            subjectIDs: [utterance.speakerID, percept.characterID],
            placeID: utterance.placeEvidence?.placeID,
            epistemic: EpistemicState(type: .reported, confidence: utterance.confidence),
            payload: percept,
            causedBy: utterance.causedBy,
            trace: utterance.trace
        )
        let acceptance = try await world.accept(envelope)
        if acceptance.disposition == .accepted, let sceneToOpen, let sceneID = percept.sceneID {
            _ = try await scenes.open(
                sceneID: sceneID,
                regionID: sceneToOpen.region,
                conversationID: utterance.conversationID,
                trigger: SceneTrigger(
                    kind: .personUtterance,
                    eventID: envelope.eventID,
                    utteranceID: utterance.utteranceID,
                    speakerID: utterance.speakerID,
                    addresseeID: percept.characterID,
                    text: utterance.text
                ),
                participants: sceneToOpen.participants,
                trace: utterance.trace
            )
        }
        return acceptance.disposition == .accepted ? .accepted : .duplicate
    }
}

extension MongoWorldPersistenceProvider: WorldApplicationService {}

enum MongoWorldPersistenceProviderError: Error, Equatable, Sendable {
    case unavailable
}

struct MongoWorldPersistenceService: Service, Sendable {
    let provider: MongoWorldPersistenceProvider
    var retryInterval: Duration = .seconds(5)

    func run() async throws {
        try await PeriodicHealthCheckService(
            interval: retryInterval,
            operation: {
                await provider.connectIfNeeded()
                _ = await provider.isHealthy()
            },
            shutdown: {
                await provider.shutdown()
            }
        ).run()
    }
}
