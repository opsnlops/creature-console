import Common
import CreatureAppSupport
import Foundation
import Observation
import WorldCore

/// How the Viewer's eye on the world is doing.
enum WorldStreamState: Equatable, Sendable {
    case idle
    case connecting
    case live
    case resuming(after: Int64)
    case resnapshotting
    case failed(String)

    var label: String {
        switch self {
        case .idle: "Idle"
        case .connecting: "Connecting"
        case .live: "Live"
        case .resuming(let sequence): "Resuming after \(sequence)"
        case .resnapshotting: "Taking a new snapshot"
        case .failed(let message): "Retrying: \(message)"
        }
    }
}

/// Everything World Viewer knows about the world it is scrying.
///
/// Read-only by construction: it follows the live stream, keeps a bounded ring of recent events
/// seeded by the snapshot, and refreshes the conversation panels when the conversation moves.
/// It is an in-memory window on the world, not a cache of record.
@MainActor
@Observable
final class WorldStore {
    static let maximumEvents = 2_000

    private(set) var health: WorldHealth?
    private(set) var streamState: WorldStreamState = .idle
    private(set) var events: [WorldEventEnvelope] = []
    private(set) var latestSequence: Int64?
    private(set) var facts: [Fact] = []
    private(set) var factsTruncated = false
    /// The Information Bridge's last heartbeat, remembered after it expires so the health
    /// line can say "not heard from since 5:44 PM" rather than nothing.
    private(set) var bridgeHeartbeat: BridgeHeartbeat?

    struct BridgeHeartbeat: Equatable, Sendable {
        var text: String
        var heardAt: Date
        var validTo: Date?
        /// The world still holds it: the Bridge is alive as far as the world knows.
        func isCurrent(at now: Date) -> Bool { validTo.map { $0 > now } ?? true }
    }
    /// The world's glossary: what each predicate means to its minds.
    private(set) var factKinds: [FactKind] = []
    private(set) var timers: [WorldTimer] = []
    private(set) var characters: [CharacterSession] = []
    private(set) var scenes: [WorldCore.Scene] = []
    private(set) var conversationItems: [ConversationItem] = []
    private(set) var deliveries: [ResponseID: CharacterDeliveryRecord] = [:]
    private(set) var conversationID: ConversationID
    private(set) var worldURI: String
    var lastError: ErrorAlert?

    @ObservationIgnored private let connection: WorldViewerConnection
    @ObservationIgnored private let makeScryer: @MainActor () throws -> any WorldScrying
    @ObservationIgnored private let reconnectDelay: Duration
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var conversationTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    convenience init(connection: WorldViewerConnection = .shared) {
        self.init(connection: connection, makeScryer: { try connection.scryer() })
    }

    /// Tests hand in a scripted world; the app hands in the live one.
    init(
        connection: WorldViewerConnection,
        reconnectDelay: Duration = .seconds(2),
        makeScryer: @escaping @MainActor () throws -> any WorldScrying
    ) {
        self.connection = connection
        self.reconnectDelay = reconnectDelay
        self.makeScryer = makeScryer
        conversationID = connection.conversationID
        worldURI = connection.worldURI
    }

    // MARK: - Lifecycle

    /// Starts (or restarts, after a settings change) following the world.
    func start() {
        stop()
        conversationID = connection.conversationID
        worldURI = connection.worldURI
        events = []
        latestSequence = nil
        facts = []
        timers = []
        conversationItems = []
        deliveries = [:]
        characters = []
        scenes = []
        health = nil
        streamTask = Task { await followWorld() }
        conversationTask = Task { await followConversation() }
    }

    func stop() {
        streamTask?.cancel()
        conversationTask?.cancel()
        expiryTask?.cancel()
        streamTask = nil
        conversationTask = nil
        streamState = .idle
    }

    /// User-initiated refresh: failures are reported. The follower loops call the loaders
    /// directly and show trouble through `streamState` instead of an alert every retry.
    func refreshConversation() async {
        do {
            try await loadConversation()
        } catch {
            lastError = ErrorAlert(title: "The Conversation Is Out Of Reach", error: error)
        }
    }

    /// User-initiated refresh of who is logged in.
    func refreshCharacters() async {
        do {
            try await loadCharacters()
        } catch {
            lastError = ErrorAlert(title: "The Characters Are Out Of Reach", error: error)
        }
    }

    func refreshScenes() async {
        do {
            try await loadScenes()
        } catch {
            lastError = ErrorAlert(title: "The Scenes Are Out Of Reach", error: error)
        }
    }

    private func loadScenes() async throws {
        let page = try await makeScryer().scenes(limit: 50)
        guard !Task.isCancelled else { return }
        scenes = page.scenes
    }

    private func loadCharacters() async throws {
        let page = try await makeScryer().characters()
        guard !Task.isCancelled else { return }
        characters = page.sessions
    }

    func refreshFactsAndTimers() async {
        do {
            let scryer = try makeScryer()
            let limit = WorldViewerClient.maximumPageSize
            async let factPage = scryer.facts(limit: limit)
            async let timerPage = scryer.timers(limit: limit)
            async let kindPage = scryer.factKinds()
            let (loadedFacts, loadedTimers, loadedKinds) = try await (factPage, timerPage, kindPage)
            guard !Task.isCancelled else { return }
            facts = loadedFacts.facts
            sweepExpiredFacts()
            factsTruncated = loadedFacts.hasMore
            timers = loadedTimers.timers
            factKinds = loadedKinds.kinds
        } catch {
            lastError = ErrorAlert(title: "Facts And Timers Are Out Of Reach", error: error)
        }
    }

    /// Predicates the world currently believes something under but has no meaning for yet:
    /// new words for the Wizard to define.
    var undefinedPredicates: [String] {
        let known = Set(factKinds.map(\.predicate))
        return Array(Set(facts.map(\.predicate)).subtracting(known)).sorted()
    }

    /// A bird learned something April did not mean it to keep: retract it.
    func forget(_ subjectID: EntityID, _ predicate: String) async {
        do {
            guard let caster = try makeScryer() as? any WorldCasting else {
                throw WorldConversationClientError.unexpectedResponse
            }
            try await caster.forget(subjectID, predicate, by: "wizard:april")
        } catch {
            lastError = ErrorAlert(title: "The World Did Not Forget", error: error)
        }
    }

    /// The entity April has asked to see whole; the root view turns to the Entities panel.
    var chosenEntity: EntityID?

    /// Everything the world currently believes something about, by kind then name.
    var knownEntities: [EntityID] {
        Array(Set(facts.map(\.subjectID))).sorted { $0.rawValue < $1.rawValue }
    }

    /// One entity, whole, from the world.
    func entity(_ entityID: EntityID) async -> EntityPage? {
        do {
            return try await makeScryer().entity(entityID)
        } catch {
            lastError = ErrorAlert(
                title: "The World Could Not Show \(entityID.rawValue)", error: error)
            return nil
        }
    }

    /// Who a kind of fact is for, as the glossary says; `minds` when it says nothing.
    func audience(of predicate: String) -> FactAudience {
        factKinds.first { $0.predicate == predicate }?.audience ?? .minds
    }

    /// Wizard Mode's casts on the glossary: reword what a kind of fact means, or say who it is
    /// for. The world remembers who did.
    func reword(_ predicate: String, meaning: String, audience: FactAudience? = nil) async {
        do {
            guard let caster = try makeScryer() as? any WorldCasting else {
                throw WorldConversationClientError.unexpectedResponse
            }
            let kind = try await caster.setFactKind(
                predicate, meaning: meaning, audience: audience, by: "wizard:april")
            guard !Task.isCancelled else { return }
            if let index = factKinds.firstIndex(where: { $0.predicate == predicate }) {
                factKinds[index] = kind
            } else {
                factKinds.append(kind)
                factKinds.sort { $0.predicate < $1.predicate }
            }
        } catch {
            lastError = ErrorAlert(title: "The World Did Not Take The Meaning", error: error)
        }
    }

    /// How much of the conversation the panel keeps: the newest of it. The whole history is
    /// the nightly memory's business, not the window's.
    static let maximumConversationItems = 500

    /// The conversation is served oldest first, a page at a time: the first load walks every
    /// page to the end (the house has said more than a page's worth), and each update asks
    /// only for what came after the last item seen.
    private func loadConversation() async throws {
        let scryer = try makeScryer()
        let limit = WorldViewerClient.maximumPageSize
        var items = conversationItems
        var after = items.last?.itemID
        while true {
            let page = try await scryer.conversationItems(
                in: conversationID, after: after, limit: limit)
            guard !Task.isCancelled else { return }
            items += page.items
            guard page.hasMore, let last = page.items.last else { break }
            after = last.itemID
        }
        let loadedDeliveries = try await scryer.deliveries(in: conversationID, limit: limit)
        guard !Task.isCancelled else { return }
        conversationItems = Array(items.suffix(Self.maximumConversationItems))
        deliveries = Dictionary(
            loadedDeliveries.deliveries.map { ($0.intent.responseID, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    // MARK: - Following the world

    private func followWorld() async {
        var resumeAfter: Int64? = nil
        while !Task.isCancelled {
            streamState = resumeAfter.map { .resuming(after: $0) } ?? .connecting
            do {
                let scryer = try makeScryer()
                health = try await scryer.health()
                let frames = try scryer.worldFrames(resumeAfter: resumeAfter)
                var resnapshot = false
                for try await frame in frames {
                    guard !Task.isCancelled else { return }
                    switch frame {
                    case .snapshot(let snapshot):
                        latestSequence = snapshot.latestSequence
                        facts = snapshot.facts
                        for fact in snapshot.facts { noteBridgeHeartbeat(fact) }
                        sweepExpiredFacts()
                        factsTruncated = snapshot.factsTruncated
                        timers = snapshot.timers
                        try await loadRecentHistory(using: scryer, upTo: snapshot.latestSequence)
                        try await loadCharacters()
                        try await loadScenes()
                        streamState = .live
                    case .event(let event):
                        append(event)
                        streamState = .live
                    case .delta(let delta):
                        append(delta.event)
                        apply(changedFacts: delta.changedFacts)
                        streamState = .live
                    case .resnapshotRequired:
                        resnapshot = true
                    }
                }
                if resnapshot {
                    streamState = .resnapshotting
                    resumeAfter = nil
                } else {
                    resumeAfter = latestSequence
                }
            } catch is CancellationError {
                return
            } catch {
                streamState = .failed(ServerError.detailedMessage(from: error))
                resumeAfter = latestSequence
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: reconnectDelay)
        }
    }

    /// Seeds the timeline with the newest events up to the snapshot so the window is not empty
    /// until something happens.
    private func loadRecentHistory(using scryer: any WorldScrying, upTo sequence: Int64)
        async throws
    {
        let window = Int64(Self.maximumEvents)
        var cursor = max(0, sequence - window)
        var loaded: [WorldEventEnvelope] = []
        while true {
            let page = try await scryer.events(
                after: cursor, limit: WorldViewerClient.maximumPageSize)
            loaded.append(contentsOf: page.events.filter { ($0.worldSequence ?? 0) <= sequence })
            guard page.hasMore, page.nextSequence > cursor, page.nextSequence < sequence else {
                break
            }
            cursor = page.nextSequence
        }
        guard !Task.isCancelled else { return }
        events = Array(loaded.suffix(Self.maximumEvents))
    }

    private func append(_ event: WorldEventEnvelope) {
        guard let sequence = event.worldSequence else { return }
        if let latest = latestSequence, sequence <= latest,
            events.contains(where: { $0.eventID == event.eventID })
        {
            return
        }
        events.append(event)
        if events.count > Self.maximumEvents {
            events.removeFirst(events.count - Self.maximumEvents)
        }
        latestSequence = max(latestSequence ?? 0, sequence)
        if event.type.rawValue.hasPrefix("character.") {
            Task { try? await loadCharacters() }
        }
        if event.type.rawValue.hasPrefix("scene.") {
            Task { try? await loadScenes() }
        }
    }

    /// A delta carries the fact that changed, not the one it replaced: the world closes the
    /// older fact about the same subject and predicate as it saves the new one, so the Viewer
    /// applies the same rule rather than showing two "current" answers until a refresh.
    private func apply(changedFacts: [Fact]) {
        for fact in changedFacts {
            noteBridgeHeartbeat(fact)
            facts.removeAll {
                $0.factID != fact.factID && $0.subjectID == fact.subjectID
                    && $0.predicate == fact.predicate
            }
            if let index = facts.firstIndex(where: { $0.factID == fact.factID }) {
                facts[index] = fact
            } else {
                facts.append(fact)
            }
        }
        sweepExpiredFacts()
    }

    /// A fact with a validity window leaves the list when the window closes, not at the next
    /// refresh: the world sends no delta for an expiry, so the Viewer keeps its own alarm for the
    /// soonest one (a Forget is a fact valid for one second).
    static let bridgeHeartbeatPredicate = "bridge.online"

    private func noteBridgeHeartbeat(_ fact: Fact) {
        guard fact.predicate == Self.bridgeHeartbeatPredicate, fact.supersededBy == nil,
            case .string(let text) = fact.value,
            bridgeHeartbeat.map({ fact.validFrom >= $0.heardAt }) ?? true
        else { return }
        bridgeHeartbeat = BridgeHeartbeat(
            text: text, heardAt: fact.validFrom, validTo: fact.validTo)
    }

    private func sweepExpiredFacts() {
        let now = Date()
        facts.removeAll { $0.supersededBy != nil || ($0.validTo.map { $0 <= now } ?? false) }
        expiryTask?.cancel()
        guard let next = facts.compactMap(\.validTo).min() else { return }
        expiryTask = Task {
            try? await Task.sleep(for: .seconds(max(0.05, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            sweepExpiredFacts()
        }
    }

    /// Beaky's turns arrive on the conversation stream, not the world stream: her mind posts
    /// through the router, which publishes the canonical item to conversation subscribers.
    private func followConversation() async {
        while !Task.isCancelled {
            do {
                let scryer = try makeScryer()
                let updates = try scryer.conversationUpdates(in: conversationID)
                try await loadConversation()
                for try await _ in updates {
                    guard !Task.isCancelled else { return }
                    try await loadConversation()
                }
            } catch is CancellationError {
                return
            } catch {
                // The world stream's state already says the world is out of reach; the next
                // connection reconciles from canonical history.
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: reconnectDelay)
        }
    }
}
