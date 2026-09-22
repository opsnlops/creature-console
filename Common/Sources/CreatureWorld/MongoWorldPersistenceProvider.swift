import AsyncHTTPClient
import Foundation
import Logging
import Observability
import ServiceLifecycle
import WorldCore

struct MongoWorldPersistenceConnection: Sendable {
    let acceptEvent: @Sendable (WorldEventEnvelope) async throws -> WorldEventAcceptance
    let events: @Sendable (Int64, Int) async throws -> WorldEventPage
    let currentFacts: @Sendable (EntityID?, String?, FactID?, Int) async throws -> WorldFactPage
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
    let factKinds: @Sendable () async throws -> FactKindPage
    let setFactKind: @Sendable (String, FactKindUpdate) async throws -> FactKind
    let dayDigest: @Sendable (String) async throws -> DayDigest?
    let remember: @Sendable (String) async throws -> WorldEventAcceptance
    let entity: @Sendable (EntityID) async throws -> EntityPage
    let perspective: @Sendable (EntityID, String?) async throws -> CharacterPerspective
    let explain: @Sendable (FactID) async throws -> FactExplanation?
    let entityNamed: @Sendable (String) async throws -> EntityID?
    let search: @Sendable (String, Int) async throws -> WorldSearchPage
    let memories: @Sendable (EntityID, Int) async throws -> [Fact]
    let shutdown: @Sendable () async -> Void

    init(
        persistence: MongoWorldPersistence,
        presence: PresenceConfiguration = PresenceConfiguration(),
        creatureServer: CreatureServerConfiguration? = nil,
        sceneLimits: SceneLimits = SceneLimits(),
        scenePerformance: ScenePerformanceMode = .streaming,
        regions: [EntityID: RegionConfiguration] = [:],
        leadCharacter: EntityID = CreatureWorldConfiguration.defaultLeadCharacter,
        houseConversation: ConversationID = CreatureWorldConfiguration.defaultHouseConversation,
        givenFacts: [GivenFact] = [],
        memory: MemoryConfiguration = MemoryConfiguration(),
        calendar: CalendarRuleConfiguration = CalendarRuleConfiguration(),
        departures: DepartureRuleConfiguration = DepartureRuleConfiguration(),
        reminders: ReminderRuleConfiguration = ReminderRuleConfiguration(),
        house: EntityID = CreatureWorldConfiguration.defaultHouse,
        publishConversationItem: @escaping @Sendable (ConversationItem) async -> Void = { _ in },
        clock: any WorldClock = SystemWorldClock(),
        logger: Logger
    ) throws {
        let world = World(
            eventStore: persistence.events,
            factStore: persistence.facts,
            reducers: [
                CharacterPresenceReducer(), AssumedPersonPresenceReducer(), SceneMemoryReducer(),
                GivenFactReducer(), HouseReducer(),
            ],
            clock: clock
        )
        let timerScheduler = WorldTimerScheduler(
            store: persistence.timers,
            eventSink: world,
            clock: clock,
            logger: logger
        )
        let deliveryRouter = try CharacterDeliveryRouter(
            presenceProvider: FactBackedPresenceProvider(
                facts: persistence.facts,
                fallback: AssumedPresenceProvider(configuration: presence, clock: clock),
                assumptions: presence, clock: clock),
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
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: sessionService, regions: regions, clock: clock, memory: memory)
        let sceneService = SceneService(
            repository: persistence.scenes,
            clock: clock,
            limits: sceneLimits,
            performer: performer,
            knowledge: knowledge,
            announce: { _ = try await world.accept($0) },
            scheduleDeadline: { try await timerScheduler.schedule($0) },
            cancelDeadline: { try await timerScheduler.cancel(timerID: $0) },
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
                sessions: sessionService, rule: LeadAddresseeRule(lead: leadCharacter)),
            knowledge: knowledge,
            houseCommands: HouseSceneRequests(
                facts: persistence.facts, world: world, clock: clock, logger: logger)
        )
        // What the world assumes about people is a fact with provenance, announced at startup
        // (idempotent: the same assumption is the same event on every restart).
        let assumptionAnnouncer = Task {
            do {
                let now = await clock.now
                for event in try AssumedPresenceAnnouncement.events(for: presence, at: now)
                    + GivenFactAnnouncement.events(for: givenFacts, at: now)
                {
                    _ = try await world.accept(event)
                }
            } catch {
                logger.warning(
                    "Could not announce presence assumptions", metadata: ["error": "\(error)"])
            }
        }
        // A mind whose heartbeat stopped is logged out by the world, so presence facts follow.
        let sessionSweeper = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                do {
                    try await sessionService.sweepExpired()
                } catch {
                    logger.warning(
                        "Could not sweep expired character sessions",
                        metadata: ["error": "\(error)"])
                }
            }
        }
        // The calendar's rule: an event at the house with a person April knows, within a day, is
        // a visitor expected - the same fact April casts by saying so.
        let visitorRule = VisitorRule(atHome: calendar.atHome, facts: persistence.facts) {
            _ = try await world.accept($0)
        }
        // And the orders' rule: out for delivery is a delivery expected at the house today,
        // delivered is a delivery arrived - the founding moment, as a rule, not a special case.
        let deliveryRule = DeliveryRule(house: house, facts: persistence.facts, zone: memory.zone) {
            _ = try await world.accept($0)
        }
        // And the departures' rule: an away event's leave-by time drawing near while April is
        // home is the house's own occasion - the plan's "you'll miss the ferry".
        let departureRule = DepartureRule(
            configuration: departures, atHome: calendar.atHome, house: house, zone: memory.zone,
            facts: persistence.facts
        ) { _ = try await world.accept($0) }
        // And the reminders' rule: one of April's reminders falling due while she is home is
        // the house's occasion, once.
        let reminderRule = ReminderRule(
            configuration: reminders, house: house, zone: memory.zone, facts: persistence.facts
        ) { _ = try await world.accept($0) }
        let visitorSweeper = Task {
            while !Task.isCancelled {
                do {
                    try await visitorRule.sweep(now: await clock.now)
                    try await deliveryRule.sweep(now: await clock.now)
                    try await departureRule.sweep(now: await clock.now)
                    try await reminderRule.sweep(now: await clock.now)
                } catch {
                    logger.warning(
                        "Could not read the calendar or the orders",
                        metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
        // The house starts scenes: a person at the driveway, a door unlocking. The rules are
        // `scenes.open_on`; the lead gets the floor first, then whoever else is in the region.
        let openingPolicy = SceneOpeningPolicy(
            rules: sceneLimits.openOn, considerRules: sceneLimits.considerOn,
            gapSeconds: sceneLimits.houseGapSeconds, quietHours: sceneLimits.quietHours)
        let sceneOpener = Task {
            guard !sceneLimits.openOn.isEmpty || !sceneLimits.considerOn.isEmpty else { return }
            do {
                for try await delta in try await world.subscribe() {
                    let event = delta.event
                    // The house's word on who a camera saw, into the record - whether or not
                    // the sighting opens a scene.
                    if event.type == HouseEvents.personSeen,
                        let seenAt = event.placeID ?? event.subjectIDs.first,
                        let identified = try Household.identification(
                            of: event, place: seenAt,
                            situation: try await Household.situation(
                                facts: persistence.facts, at: await clock.now),
                            now: await clock.now)
                    {
                        _ = try await world.accept(identified)
                    }
                    guard
                        let occasion = await openingPolicy.occasion(for: event, at: await clock.now)
                    else { continue }
                    let place = occasion.place
                    // The region the place belongs to; a person's region is wherever the lead is.
                    var regionID = regions.first { $0.value.places.contains(place) }?.key
                    if regionID == nil {
                        regionID = try await sessionService.liveSession(for: leadCharacter)?
                            .regionID
                    }
                    guard let regionID else { continue }
                    let present = try await sessionService.present(in: regionID).map(\.characterID)
                    guard !present.isEmpty else { continue }
                    // A question from the house never interrupts a conversation already going;
                    // a must-speak occasion still does.
                    if occasion.kind == .houseConsideration,
                        try await sceneService.hasOpenScene(in: regionID)
                    {
                        continue
                    }
                    let participants =
                        present.contains(leadCharacter)
                        ? [leadCharacter] + present.filter { $0 != leadCharacter } : present
                    let scene = try await sceneService.open(
                        regionID: regionID,
                        conversationID: houseConversation,
                        trigger: SceneTrigger(
                            kind: occasion.kind, eventID: event.eventID,
                            text: SceneOpeningPolicy.triggerText(
                                for: event, place: place,
                                household: try await Household.situation(
                                    facts: persistence.facts, at: await clock.now))),
                        participants: participants,
                        trace: event.trace)
                    logger.info(
                        occasion.kind == .houseConsideration
                            ? "The house asked the lead about something"
                            : "The house opened a scene",
                        metadata: [
                            "scene.id": "\(scene.sceneID.rawValue)",
                            "world.event_type": "\(event.type.rawValue)",
                            "place": "\(place.rawValue)",
                        ])
                }
            } catch {
                logger.warning(
                    "Stopped opening scenes for the house", metadata: ["error": "\(error)"])
            }
        }
        // Floor deadlines fire as world timers; the scene service hears them from the stream.
        let floorWatcher = Task {
            do {
                for try await delta in try await world.subscribe() {
                    guard case .string(let rawScene)? = delta.event.payload["scene_id"],
                        let sceneID = SceneID(rawValue: rawScene)
                    else { continue }
                    switch delta.event.type {
                    case SceneService.floorExpiredEventType:
                        guard case .string(let rawResponse)? = delta.event.payload["response_id"],
                            let responseID = ResponseID(rawValue: rawResponse)
                        else { continue }
                        try await sceneService.floorExpired(
                            sceneID: sceneID, responseID: responseID)
                    case SceneService.floorReadyEventType:
                        try await sceneService.floorReady(sceneID: sceneID)
                    default:
                        continue
                    }
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
        currentFacts = { subjectID, predicatePrefix, after, limit in
            let loaded = try await persistence.facts.currentFacts(
                subjectID: subjectID,
                predicatePrefix: predicatePrefix,
                after: after,
                limit: limit + 1,
                at: await clock.now
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
                limit: limit + 1,
                at: await clock.now
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
        recoverTimers = {
            try await timerScheduler.recover()
            // The world's own catalogue of what its predicates mean, for any the store lacks.
            try await persistence.factKinds.seed(WorldFacts.meanings, at: await clock.now)
        }
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
        factKinds = { FactKindPage(kinds: try await persistence.factKinds.all()) }
        dayDigest = { day in
            try await DayDigestBuilder(
                persistence: persistence, houseConversation: houseConversation, memory: memory
            ).digest(of: day)
        }
        remember = { day in
            try await world.accept(
                MemoryClock.request(day: day, memory: memory, now: await clock.now))
        }
        // The memory clock: one world timer for the next consolidation, rescheduled after each
        // firing. The mind that owns a memory model hears the timer's event and does the work.
        let memoryClock = Task {
            do {
                try await MemoryClock.schedule(after: await clock.now, memory: memory) {
                    try await timerScheduler.schedule($0)
                }
                for try await delta in try await world.subscribe()
                where delta.event.type == MemoryClock.eventType {
                    try await MemoryClock.schedule(after: await clock.now, memory: memory) {
                        try await timerScheduler.schedule($0)
                    }
                }
            } catch {
                logger.warning("Stopped keeping the memory clock", metadata: ["error": "\(error)"])
            }
        }
        setFactKind = { predicate, update in
            try await persistence.factKinds.set(
                predicate, meaning: update.meaning, audience: update.audience,
                by: update.updatedBy, at: await clock.now)
        }
        entity = { entityID in
            try await knowledge.entityPage(entityID, now: await clock.now)
        }
        // What a mind would be handed: the same gathering a scene offer does, for the
        // character, every region, and April.
        perspective = { characterID, text in
            let now = await clock.now
            let subjects =
                [characterID] + Array(regions.keys).sorted { $0.rawValue < $1.rawValue }
                + [try EntityID(validating: "person:april")]
            let facts = try await knowledge.currentFacts(
                about: subjects, mentionedIn: text, limit: WorldKnowledgeLimits.maximumFacts)
            return CharacterPerspective(
                characterID: characterID, facts: facts,
                factMeanings: try await knowledge.meanings(of: Set(facts.map(\.predicate))),
                recentHappenings: try await knowledge.recentHappenings(
                    about: subjects,
                    since: now.addingTimeInterval(-WorldKnowledgeLimits.happeningsWindow),
                    limit: WorldKnowledgeLimits.maximumHappenings),
                recentLines: try await knowledge.recentLines(
                    of: characterID, limit: WorldKnowledgeLimits.maximumRecentLines))
        }
        // Search: MongoDB's text index over every fact, grouped by entity, best first, with
        // the facts that matched. One query answers "who is Tamara?", "the cleaner", or
        // "toothpaste" - a mind never has to guess at an id.
        let search: @Sendable (String, Int) async throws -> WorldSearchPage = { query, limit in
            let now = await clock.now
            let scored = try await persistence.facts.search(
                query, limit: max(limit, 1) * WorldSearchLimits.factsPerEntity, at: now)
            var order: [EntityID] = []
            var hits: [EntityID: WorldSearchHit] = [:]
            for (fact, score) in scored {
                if var hit = hits[fact.subjectID] {
                    if hit.facts.count < WorldSearchLimits.factsPerEntity {
                        hit.facts.append(fact)
                    }
                    hit.score = max(hit.score, score)
                    hits[fact.subjectID] = hit
                } else {
                    order.append(fact.subjectID)
                    hits[fact.subjectID] = WorldSearchHit(
                        entityID: fact.subjectID, score: score, facts: [fact])
                }
            }
            return WorldSearchPage(
                query: query,
                hits: order.prefix(limit).compactMap { hits[$0] }.sorted { $0.score > $1.score })
        }
        self.search = search
        // What one bird remembers, on any subject: its own memories, newest first.
        memories = { bird, limit in
            try await persistence.facts.currentFacts(
                rememberedBy: bird, limit: max(limit, 1), at: await clock.now)
        }
        // A name the world knows, as an entity: "Tamara" or "my mom" by the people the world
        // can describe (relationship words and their synonyms count); anything else by the
        // text index. A mind asking a tool guesses at ids; the world knows.
        entityNamed = { name in
            let now = await clock.now
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains(":"), let id = EntityID(rawValue: trimmed) { return id }
            if let person = WorldMentions.mentioned(
                in: trimmed, among: try await knowledge.knownPeople(at: now)
            ).first {
                return person
            }
            return try await search(trimmed, 1).hits.first?.entityID
        }
        // Why: the fact, then whatever it was derived from, a few levels down, nearest first.
        explain = { factID in
            guard let fact = try await persistence.facts.fact(withID: factID) else { return nil }
            var events: [WorldEventEnvelope] = []
            var facts: [Fact] = []
            var frontier = fact.derivedFrom
            var seen: Set<String> = [factID.rawValue]
            for _ in 0..<4 where !frontier.isEmpty {
                var next: [ProvenanceReference] = []
                for reference in frontier {
                    guard seen.insert(reference.description).inserted else { continue }
                    switch reference {
                    case .event(let eventID):
                        if let event = try await persistence.events.event(withID: eventID) {
                            events.append(event)
                        }
                    case .fact(let id):
                        if let earlier = try await persistence.facts.fact(withID: id) {
                            facts.append(earlier)
                            next += earlier.derivedFrom
                        }
                    }
                }
                frontier = next
            }
            var successor: Fact?
            if let successorID = fact.supersededBy {
                successor = try await persistence.facts.fact(withID: successorID)
            }
            return FactExplanation(
                fact: fact, events: events, facts: facts, supersededBy: successor)
        }
        shutdown = {
            visitorSweeper.cancel()
            memoryClock.cancel()
            assumptionAnnouncer.cancel()
            sessionSweeper.cancel()
            floorWatcher.cancel()
            sceneOpener.cancel()
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
        currentFacts:
            @escaping @Sendable (EntityID?, String?, FactID?, Int) async throws ->
            WorldFactPage =
            {
                _, _, _, _ in throw WorldAPIError.databaseUnavailable
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
        factKinds: @escaping @Sendable () async throws -> FactKindPage = {
            throw WorldAPIError.databaseUnavailable
        },
        setFactKind: @escaping @Sendable (String, FactKindUpdate) async throws -> FactKind = {
            _, _ in throw WorldAPIError.databaseUnavailable
        },
        remember: @escaping @Sendable (String) async throws -> WorldEventAcceptance = { _ in
            throw WorldAPIError.databaseUnavailable
        },
        entity: @escaping @Sendable (EntityID) async throws -> EntityPage = { _ in
            throw WorldAPIError.databaseUnavailable
        },
        perspective: @escaping @Sendable (EntityID, String?) async throws -> CharacterPerspective =
            { _, _ in throw WorldAPIError.databaseUnavailable },
        explain: @escaping @Sendable (FactID) async throws -> FactExplanation? = { _ in
            throw WorldAPIError.databaseUnavailable
        },
        entityNamed: @escaping @Sendable (String) async throws -> EntityID? = { _ in nil },
        search: @escaping @Sendable (String, Int) async throws -> WorldSearchPage = { _, _ in
            throw WorldAPIError.databaseUnavailable
        },
        memories: @escaping @Sendable (EntityID, Int) async throws -> [Fact] = { _, _ in
            throw WorldAPIError.databaseUnavailable
        },
        dayDigest: @escaping @Sendable (String) async throws -> DayDigest? = {
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
        self.factKinds = factKinds
        self.setFactKind = setFactKind
        self.dayDigest = dayDigest
        self.remember = remember
        self.entity = entity
        self.perspective = perspective
        self.explain = explain
        self.entityNamed = entityNamed
        self.search = search
        self.memories = memories
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
        houseConversation: ConversationID = CreatureWorldConfiguration.defaultHouseConversation,
        givenFacts: [GivenFact] = [],
        retention: RetentionPolicy = RetentionPolicy(),
        memory: MemoryConfiguration = MemoryConfiguration(),
        calendar: CalendarRuleConfiguration = CalendarRuleConfiguration(),
        departures: DepartureRuleConfiguration = DepartureRuleConfiguration(),
        reminders: ReminderRuleConfiguration = ReminderRuleConfiguration(),
        house: EntityID = CreatureWorldConfiguration.defaultHouse,
        logger: Logger,
        connector: Connector? = nil
    ) {
        self.uri = uri
        self.logger = logger
        let conversationUpdates = self.conversationUpdates
        self.connector =
            connector ?? { uri, logger in
                let persistence = try await MongoWorldPersistence.connect(
                    to: uri, logger: logger, retention: retention)
                do {
                    return try MongoWorldPersistenceConnection(
                        persistence: persistence,
                        presence: presence,
                        creatureServer: creatureServer,
                        sceneLimits: sceneLimits,
                        scenePerformance: scenePerformance,
                        regions: regions,
                        leadCharacter: leadCharacter,
                        houseConversation: houseConversation,
                        givenFacts: givenFacts,
                        memory: memory,
                        calendar: calendar,
                        departures: departures,
                        reminders: reminders,
                        house: house,
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

    func currentFacts(
        subjectID: EntityID?, predicatePrefix: String?, after: FactID?, limit: Int
    ) async throws -> WorldFactPage {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.currentFacts(subjectID, predicatePrefix, after, limit)
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

    func factKinds() async throws -> FactKindPage {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.factKinds()
    }

    func setFactKind(_ predicate: String, _ update: FactKindUpdate) async throws -> FactKind {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.setFactKind(predicate, update)
    }

    func dayDigest(_ day: String) async throws -> DayDigest? {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.dayDigest(day)
    }

    func remember(_ day: String) async throws -> WorldEventAcceptance {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.remember(day)
    }

    func entity(_ entityID: EntityID) async throws -> EntityPage {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.entity(entityID)
    }

    func perspective(of characterID: EntityID, mentionedIn text: String?) async throws
        -> CharacterPerspective
    {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.perspective(characterID, text)
    }

    func explain(factID: FactID) async throws -> FactExplanation? {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.explain(factID)
    }

    func entity(named name: String) async throws -> EntityID? {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.entityNamed(name)
    }

    func search(_ query: String, limit: Int) async throws -> WorldSearchPage {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.search(query, limit)
    }

    func memories(of characterID: EntityID, limit: Int) async throws -> [Fact] {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.memories(characterID, limit)
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

/// What the world knows that bears on a moment: facts about the subjects asked for, plus the
/// region the character is in and everyone logged into it — so "who is here with you" and
/// "what was just said in this room" ride along without the caller knowing about regions.
struct PresentWorldKnowledge: WorldKnowledgeProviding {
    let facts: FactRepository
    let events: WorldEventRepository
    let kinds: FactKindRepository
    let sessions: CharacterSessionService
    let regions: [EntityID: RegionConfiguration]
    let clock: any WorldClock
    var memory = MemoryConfiguration()

    func currentFacts(about subjects: [EntityID], mentionedIn text: String?, limit: Int)
        async throws -> [Fact]
    {
        let now = await clock.now
        var expanded = try await surroundings(of: subjects)
        // Anyone the world can describe who is named in the words - "Who is Polly?" - or
        // called by what they are to April: "when is my mom's birthday?".
        if let text, !text.isEmpty {
            expanded.append(
                contentsOf: WorldMentions.mentioned(in: text, among: try await knownPeople(at: now))
            )
            // And orders, by what was in them: "did I order a servo?".
            expanded.append(
                contentsOf: WorldMentions.mentioned(in: text, among: try await knownOrders(at: now))
            )
            // And the newest orders whenever orders are the subject: "did I just order
            // toothpaste?" when the mail only said "1 Personal Care item".
            let words = Set(
                text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            if !words.isDisjoint(with: WorldKnowledgeLimits.orderWords) {
                expanded.append(contentsOf: try await recentOrders(at: now))
            }
        }
        // What is the world's alone stays with the world - and never takes a mind's place on
        // the capped page.
        var worldOnly = try await kinds.worldOnlyPredicates()
        // And kinds that ride only on request: a bird's body is thirty lines a clock question
        // does not need; the words "board", "power", "servo" bring them.
        let wordsInText = Set(
            (text ?? "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        for (prefix, words) in WorldKnowledgeLimits.onRequestPrefixes
        where wordsInText.isDisjoint(with: words) {
            worldOnly.formUnion(try await kinds.predicates(withPrefix: prefix))
        }
        // The day's facts and the memories are capped separately: a night's episodes are many
        // and newer than everything else, and would otherwise push what April taught the birds
        // yesterday off the page.
        let about = unique(expanded)
        var present = try await facts.currentFacts(
            about: about, family: .notMemories, excluding: worldOnly, limit: limit, at: now)
        // Links, one hop: a fact whose value is an entity (`calendar.with = person:jesse`)
        // brings that entity's facts along, so a bird handed the visit is handed the visitor.
        // One hop only, and never on the live line's critical path a second time.
        let linked = unique(present.compactMap { WorldFacts.link(in: $0.value) })
            .filter { !about.contains($0) }
        if !linked.isEmpty {
            present += try await facts.currentFacts(
                about: linked, family: .notMemories, excluding: worldOnly, limit: limit, at: now)
        }
        // Memories are the mind's own: the first character among the subjects is the mind
        // being handed this (every caller puts it first), and what Beaky remembers of April is
        // not what Kenny is told. Recent and salient ones ride along, trimmed; and the ones
        // the words of the moment call up, whatever their age - "how did the deck go?" three
        // weeks on finds the episode by its words, not its date (plan Phase 9, retrieval).
        var remembered: [Fact] = []
        var retrieved: [Fact] = []
        if let mind = subjects.first(where: { $0.rawValue.hasPrefix("character:") }) {
            remembered = Self.withMemoriesTrimmed(
                try await facts.currentFacts(
                    about: about + linked, family: .own(mind), limit: limit, at: now),
                memory: memory, now: now)
            if memory.retrievedInPrompt > 0, let text, !text.isEmpty {
                let known = Set(remembered.map(\.factID))
                retrieved = try await facts.search(
                    text, own: mind, limit: memory.retrievedInPrompt, at: now
                ).map(\.0).filter { !known.contains($0.factID) }
            }
        }
        // What is coming: the next few days of the calendar ride along with every question, a
        // fortnight when the words are about time - on a page of their own, so a busy week
        // never crowds the people and places out of theirs.
        let upcoming = try await upcomingEvents(mentionedIn: text, now: now)
            .filter { !about.contains($0) && !linked.contains($0) }
        let coming =
            upcoming.isEmpty
            ? []
            : try await facts.currentFacts(
                about: upcoming, family: .notMemories, excluding: worldOnly,
                limit: (WorldKnowledgeLimits.maximumUpcomingEvents
                    + WorldKnowledgeLimits.maximumReminders) * 4, at: now)
        return present + coming + retrieved + remembered
    }

    /// The events starting in the next three days - a fortnight when the question is about
    /// time - soonest first, at most eight; and the day's reminders - the week's when the
    /// question is about time - at most six. The calendar and the reminders are the sources
    /// whose facts matter before anyone names them.
    private func upcomingEvents(mentionedIn text: String?, now: Date) async throws -> [EntityID] {
        let words = Set(
            (text ?? "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let aboutTime = !words.isDisjoint(with: WorldKnowledgeLimits.timeWords)
        let days: TimeInterval = aboutTime ? 14 : 3
        let soon = try await facts.subjects(
            withPredicate: "calendar.starts_at", between: now.addingTimeInterval(-3 * 3_600),
            and: now.addingTimeInterval(days * 86_400), at: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = memory.zone
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: aboutTime ? 7 : 1, to: dayStart)!
        let reminders = try await facts.subjects(
            withPredicate: "reminder.due_at", between: dayStart, and: dayEnd, at: now)
        return Array(soon.prefix(WorldKnowledgeLimits.maximumUpcomingEvents))
            + Array(reminders.prefix(WorldKnowledgeLimits.maximumReminders))
    }

    /// One entity, whole, for the Viewer's page and a mind's question: every current fact
    /// about it (every audience), the facts elsewhere that point at it, and its recent events.
    func entityPage(_ entityID: EntityID, now: Date) async throws -> EntityPage {
        let about = try await facts.currentFacts(subjectID: entityID, at: now)
        let linkedFrom = try await facts.currentFacts(pointingAt: entityID, at: now)
        let recent = try await events.events(
            about: [entityID], since: now.addingTimeInterval(-7 * 86_400), limit: 50)
        return EntityPage(
            entityID: entityID, facts: about, linkedFrom: linkedFrom,
            events: recent.sorted { $0.occurredAt > $1.occurredAt })
    }

    /// Memories are kept for years but handed out sparingly: an episode only while it is
    /// recent, the newest and most salient first; a bird's own reflections newest first; and
    /// beliefs - what the month settled into - the most salient first, never aged out.
    static func withMemoriesTrimmed(_ facts: [Fact], memory: MemoryConfiguration, now: Date)
        -> [Fact]
    {
        let horizon = now.addingTimeInterval(-TimeInterval(memory.episodeDays) * 86_400)
        var episodes = facts.filter {
            WorldFacts.memoryFamily(of: $0.predicate) == WorldFacts.memoryEpisode
                && $0.validFrom >= horizon
        }
        episodes.sort {
            salience($0) > salience($1)
                || (salience($0) == salience($1) && $0.validFrom > $1.validFrom)
        }
        let keptEpisodes = Set(episodes.prefix(memory.episodesInPrompt).map(\.factID))
        let reflections = facts.filter {
            WorldFacts.memoryFamily(of: $0.predicate) == WorldFacts.memoryReflection
        }
        .sorted { $0.validFrom > $1.validFrom }
        let keptReflections = Set(reflections.prefix(memory.reflectionsInPrompt).map(\.factID))
        let beliefs = facts.filter {
            WorldFacts.memoryFamily(of: $0.predicate) == WorldFacts.memoryBelief
        }
        .sorted {
            salience($0) > salience($1)
                || (salience($0) == salience($1) && $0.validFrom > $1.validFrom)
        }
        let keptBeliefs = Set(beliefs.prefix(memory.beliefsInPrompt).map(\.factID))
        return facts.filter {
            switch WorldFacts.memoryFamily(of: $0.predicate) {
            case WorldFacts.memoryEpisode?: keptEpisodes.contains($0.factID)
            case WorldFacts.memoryReflection?: keptReflections.contains($0.factID)
            case WorldFacts.memoryBelief?: keptBeliefs.contains($0.factID)
            default: true
            }
        }
    }

    private static func salience(_ fact: Fact) -> Double {
        guard case .object(let object) = fact.value,
            case .number(let salience)? = object["salience"]
        else { return 0 }
        return salience
    }

    /// The story around `subjects`: storyworthy events for them and their surroundings, oldest
    /// first, each with the world's own sentence for it where the scene openers have one.
    func recentLines(of characterID: EntityID, limit: Int) async throws -> [SpokenLine] {
        try await events.spokenLines(of: characterID, limit: limit).reversed()
    }

    func recentHappenings(about subjects: [EntityID], since: Date, limit: Int) async throws
        -> [Happening]
    {
        let around = unique(try await surroundings(of: subjects))
        // Fetch generously: heartbeats and measurements share the index and are dropped here.
        let recent = try await events.events(about: around, since: since, limit: limit * 8)
        return recent.filter { Happening.isStoryworthy($0) }
            .suffix(limit)
            .map { event in
                let subject =
                    event.subjectIDs.first { !$0.rawValue.hasPrefix("character:") }
                    ?? event.subjectIDs.first ?? event.placeID ?? around[0]
                return Happening(
                    occurredAt: event.occurredAt, type: event.type, subjectID: subject,
                    summary: Self.summary(of: event, subject: subject))
            }
    }

    /// The store's meanings, with the world's own catalogue behind them for a predicate the
    /// store has not been told about yet.
    func meanings(of predicates: Set<String>) async throws -> [String: String] {
        let stored = try await kinds.meanings(of: predicates)
        var meanings = WorldFacts.meanings.filter { predicates.contains($0.key) }
            .merging(stored) { _, wizard in wizard }
        // A memory's predicate carries its day (`memory.episode.2026-09-13`); the meaning is
        // the family's.
        for predicate in predicates where meanings[predicate] == nil {
            if let family = WorldFacts.memoryFamily(of: predicate),
                let meaning = stored[family] ?? WorldFacts.meanings[family]
            {
                meanings[predicate] = meaning
            }
        }
        return meanings
    }

    /// The subjects plus the region each logged-in one is in, everyone present there, and the
    /// region's places — the house around them.
    /// Everyone the world can describe: by April's words (`person.description`), by the address
    /// book (`contact.name`), or by what they are to her (`person.relationship`).
    func knownPeople(at now: Date) async throws -> [WorldMentions.Known] {
        var people: [EntityID: String?] = [:]
        for predicate in [WorldFacts.personDescription, "contact.name"] {
            for subject in try await facts.subjects(withPredicate: predicate, at: now) {
                people[subject] = people[subject] ?? nil
            }
        }
        for fact in try await facts.currentFacts(
            about: [], predicate: WorldFacts.personRelationship, limit: 500, at: now)
        {
            if case .string(let relationship) = fact.value {
                people[fact.subjectID] = relationship
            }
        }
        return people.map { WorldMentions.Known(entityID: $0.key, relationship: $0.value) }
            .sorted { $0.entityID.rawValue < $1.entityID.rawValue }
    }

    /// Every order the world holds, by the words of what was in it.
    /// Orders the mail spoke of in the last two days, newest first.
    private func recentOrders(at now: Date) async throws -> [EntityID] {
        let since = now.addingTimeInterval(-WorldKnowledgeLimits.recentOrderWindow)
        return try await facts.currentFacts(
            about: [], predicate: "order.updated_at", limit: 500, at: now
        )
        .compactMap { fact -> (EntityID, Date)? in
            guard case .string(let raw) = fact.value, let at = WorldJSON.date(from: raw),
                at >= since
            else { return nil }
            return (fact.subjectID, at)
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    private func knownOrders(at now: Date) async throws -> [WorldMentions.Known] {
        try await facts.currentFacts(about: [], predicate: "order.items", limit: 500, at: now)
            .map { fact in
                var words: [String] = []
                if case .array(let items) = fact.value {
                    words = items.compactMap { if case .string(let s) = $0 { s } else { nil } }
                }
                return WorldMentions.Known(entityID: fact.subjectID, words: words)
            }
    }

    private func surroundings(of subjects: [EntityID]) async throws -> [EntityID] {
        var expanded = subjects
        for subject in subjects {
            guard let session = try await sessions.liveSession(for: subject) else { continue }
            expanded.append(session.regionID)
            expanded.append(
                contentsOf: try await sessions.present(in: session.regionID).map(\.characterID))
            expanded.append(contentsOf: regions[session.regionID]?.places ?? [])
        }
        return expanded
    }

    private func unique(_ ids: [EntityID]) -> [EntityID] {
        var seen: Set<EntityID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    /// The world's sentence for a happening, when it has one: the house events use the scene
    /// openers' words; a cast fact says who told the world what. Anything else is left to the
    /// mind's generic rendering of type and subject.
    static func summary(of event: WorldEventEnvelope, subject: EntityID) -> String? {
        if event.type == GivenFactAnnouncement.eventType {
            guard case .string(let predicate)? = event.payload["predicate"] else { return nil }
            let value: String
            switch event.payload["value"] {
            case .string(let text)?: value = "\"\(text)\""
            case .number(let number)?:
                value = number == number.rounded() ? String(Int(number)) : String(number)
            case .bool(let flag)?: value = flag ? "yes" : "no"
            case .some: value = "(something)"
            case nil: return nil
            }
            return
                "\(event.source.id.rawValue) told the world: \(subject.rawValue) \(predicate) = \(value)"
        }
        if event.source.kind == HouseEvents.sourceKind {
            return SceneOpeningPolicy.triggerText(for: event, place: subject)
        }
        return nil
    }
}

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

    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> Addressee {
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

/// With more than one character logged into the region, a remark means a scene: the world
/// hands the floor to the addressee first and the others may chime in. A bird April whispers
/// to ("@beaky …") answers alone — her word with Beaky stays between them.
private struct PresentCharactersScenePlanner: ScenePlanning {
    let sessions: CharacterSessionService

    func planScene(for utterance: PersonUtterance, addressee: Addressee) async throws -> SceneID? {
        guard !addressee.alone,
            let session = try await sessions.liveSession(for: addressee.characterID)
        else { return nil }
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
