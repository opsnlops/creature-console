import Foundation
import WorldCore

struct WorldAPIConfiguration: Equatable, Sendable {
    static let `default` = WorldAPIConfiguration()

    let maximumBodyBytes: Int
    let maximumBatchSize: Int
    let maximumConcurrentRequests: Int
    let maximumRequestDuration: Duration
    let maximumPageSize: Int
    let defaultPageSize: Int

    init(
        maximumBodyBytes: Int = 1_048_576,
        maximumBatchSize: Int = 100,
        maximumConcurrentRequests: Int = 64,
        maximumRequestDuration: Duration = .seconds(10),
        maximumPageSize: Int = 500,
        defaultPageSize: Int = 100
    ) {
        precondition(maximumBodyBytes > 0)
        precondition(maximumBatchSize > 0)
        precondition(maximumConcurrentRequests > 0)
        precondition(maximumRequestDuration > .zero)
        precondition(maximumPageSize > 0)
        precondition((1...maximumPageSize).contains(defaultPageSize))
        self.maximumBodyBytes = maximumBodyBytes
        self.maximumBatchSize = maximumBatchSize
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.maximumRequestDuration = maximumRequestDuration
        self.maximumPageSize = maximumPageSize
        self.defaultPageSize = defaultPageSize
    }
}

enum WorldAPIError: Error, Equatable, LocalizedError, Sendable {
    case databaseUnavailable
    case invalidOrigin
    case unsupportedMediaType
    case invalidQuery(name: String)
    case conversationIdentityMismatch
    case batchTooLarge(limit: Int)
    case overloaded(limit: Int)
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            "Creature World persistence is unavailable"
        case .invalidOrigin:
            "The request Origin is not allowed"
        case .unsupportedMediaType:
            "Creature World event requests require Content-Type: application/json"
        case .invalidQuery(let name):
            "The query parameter \(name) is invalid"
        case .conversationIdentityMismatch:
            "The conversation in the request body does not match the URL"
        case .batchTooLarge(let limit):
            "The event batch exceeds the limit of \(limit)"
        case .overloaded(let limit):
            "Creature World is handling the maximum of \(limit) concurrent API requests"
        case .requestTimedOut:
            "The Creature World API request exceeded its deadline"
        }
    }
}

struct WorldEventAcceptanceResponse: Codable, Equatable, Sendable {
    let disposition: WorldEventDisposition
    let event: WorldEventEnvelope
}

struct WorldEventBatchRequest: Codable, Equatable, Sendable {
    let events: [WorldEventEnvelope]
}

struct WorldEventBatchResponse: Codable, Equatable, Sendable {
    let results: [WorldEventAcceptanceResponse]
}

struct WorldAPIErrorResponse: Codable, Equatable, Sendable {
    let error: String
    let message: String
}

protocol WorldApplicationService: Sendable {
    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance
    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage
    func currentFacts(
        subjectID: EntityID?, predicatePrefix: String?, after: FactID?, limit: Int
    ) async throws -> WorldFactPage
    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    func snapshot(limit: Int) async throws -> WorldSnapshot
    func subscribe() async throws -> WorldDeltaStream
    func finishSubscriptions() async
    func factKinds() async throws -> FactKindPage
    func setFactKind(_ predicate: String, _ update: FactKindUpdate) async throws -> FactKind
    func dayDigest(_ day: String) async throws -> DayDigest?
    /// Asks the memory job to remember `day` now, ahead of (or again after) the nightly clock.
    func remember(_ day: String) async throws -> WorldEventAcceptance
    /// One entity, whole.
    func entity(_ entityID: EntityID) async throws -> EntityPage
    /// What a mind would be handed right now.
    func perspective(of characterID: EntityID, mentionedIn text: String?) async throws
        -> CharacterPerspective
    /// Why a fact is what it is.
    func explain(factID: FactID) async throws -> FactExplanation?
    /// The entity a name the world knows stands for - "Tamara", "my mom", "the front door" -
    /// or nil when it knows nobody by it. An id is returned as itself.
    func entity(named name: String) async throws -> EntityID?
    /// Anything by a word: entities ranked by how well their current facts match, each with
    /// the facts that matched.
    func search(_ query: String, limit: Int) async throws -> WorldSearchPage
    /// What one bird remembers, on any subject - its own memories, newest first.
    func memories(of characterID: EntityID, limit: Int) async throws -> [Fact]
}

extension WorldApplicationService {
    func factKinds() async throws -> FactKindPage { throw WorldAPIError.databaseUnavailable }
    func setFactKind(_ predicate: String, _ update: FactKindUpdate) async throws -> FactKind {
        throw WorldAPIError.databaseUnavailable
    }
    func dayDigest(_ day: String) async throws -> DayDigest? {
        throw WorldAPIError.databaseUnavailable
    }
    func remember(_ day: String) async throws -> WorldEventAcceptance {
        throw WorldAPIError.databaseUnavailable
    }
    func entity(_ entityID: EntityID) async throws -> EntityPage {
        throw WorldAPIError.databaseUnavailable
    }
    func perspective(of characterID: EntityID, mentionedIn text: String?) async throws
        -> CharacterPerspective
    {
        throw WorldAPIError.databaseUnavailable
    }
    func explain(factID: FactID) async throws -> FactExplanation? {
        throw WorldAPIError.databaseUnavailable
    }
    func entity(named name: String) async throws -> EntityID? { nil }
    func search(_ query: String, limit: Int) async throws -> WorldSearchPage {
        throw WorldAPIError.databaseUnavailable
    }
    func memories(of characterID: EntityID, limit: Int) async throws -> [Fact] {
        throw WorldAPIError.databaseUnavailable
    }
}

protocol ConversationApplicationService: Sendable {
    func ingest(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult
    func respond(_ intent: CharacterUtteranceIntent) async throws -> CharacterDeliveryResult
    func stage(
        _ request: CharacterStageRequest,
        in conversationID: ConversationID
    ) async throws -> CharacterStageResult
    func perform(
        _ performance: CharacterPerformance,
        in conversationID: ConversationID
    ) async throws -> CharacterDeliveryResult
    func conversationItems(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage
    func deliveries(
        in conversationID: ConversationID,
        after responseID: ResponseID?,
        limit: Int
    ) async throws -> CharacterDeliveryPage
    func subscribe(to conversationID: ConversationID) async throws -> ConversationItemStream
    func finishConversationSubscriptions() async
}

/// Character login: which mind is which character, and where.
protocol CharacterSessionApplicationService: Sendable {
    func login(
        _ characterID: EntityID,
        _ request: CharacterLoginRequest
    ) async throws -> CharacterLoginResult
    func heartbeat(
        _ characterID: EntityID,
        _ reference: CharacterSessionReference
    ) async throws -> CharacterSession
    func logout(
        _ characterID: EntityID,
        _ reference: CharacterSessionReference
    ) async throws -> CharacterSession
    func characterSessions() async throws -> [CharacterSession]
}

extension CharacterSessionService: CharacterSessionApplicationService {}

/// Scenes: the world's record of who spoke when, and the door a mind answers an offer through.
protocol SceneApplicationService: Sendable {
    func submitSceneTurn(_ submission: SceneTurnSubmission, to sceneID: SceneID) async throws
        -> SceneTurnResult
    func scene(id: SceneID) async throws -> Scene?
    func recentScenes(limit: Int) async throws -> [Scene]
}

struct UnavailableSceneApplicationService: SceneApplicationService {
    func submitSceneTurn(_ submission: SceneTurnSubmission, to sceneID: SceneID) async throws
        -> SceneTurnResult
    {
        throw WorldAPIError.databaseUnavailable
    }

    func scene(id: SceneID) async throws -> Scene? {
        throw WorldAPIError.databaseUnavailable
    }

    func recentScenes(limit: Int) async throws -> [Scene] {
        throw WorldAPIError.databaseUnavailable
    }
}

struct UnavailableCharacterSessionApplicationService: CharacterSessionApplicationService {
    func login(
        _ characterID: EntityID, _ request: CharacterLoginRequest
    ) async throws -> CharacterLoginResult {
        throw WorldAPIError.databaseUnavailable
    }

    func heartbeat(
        _ characterID: EntityID, _ reference: CharacterSessionReference
    ) async throws -> CharacterSession {
        throw WorldAPIError.databaseUnavailable
    }

    func logout(
        _ characterID: EntityID, _ reference: CharacterSessionReference
    ) async throws -> CharacterSession {
        throw WorldAPIError.databaseUnavailable
    }

    func characterSessions() async throws -> [CharacterSession] {
        throw WorldAPIError.databaseUnavailable
    }
}

struct UnavailableConversationApplicationService: ConversationApplicationService {
    func ingest(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult {
        throw WorldAPIError.databaseUnavailable
    }

    func respond(_ intent: CharacterUtteranceIntent) async throws -> CharacterDeliveryResult {
        throw WorldAPIError.databaseUnavailable
    }

    func stage(
        _ request: CharacterStageRequest,
        in conversationID: ConversationID
    ) async throws -> CharacterStageResult {
        throw WorldAPIError.databaseUnavailable
    }

    func perform(
        _ performance: CharacterPerformance,
        in conversationID: ConversationID
    ) async throws -> CharacterDeliveryResult {
        throw WorldAPIError.databaseUnavailable
    }

    func conversationItems(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage {
        throw WorldAPIError.databaseUnavailable
    }

    func deliveries(
        in conversationID: ConversationID,
        after responseID: ResponseID?,
        limit: Int
    ) async throws -> CharacterDeliveryPage {
        throw WorldAPIError.databaseUnavailable
    }

    func subscribe(to conversationID: ConversationID) async throws -> ConversationItemStream {
        throw WorldAPIError.databaseUnavailable
    }

    func finishConversationSubscriptions() async {}
}

struct UnavailableWorldApplicationService: WorldApplicationService {
    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance {
        throw WorldAPIError.databaseUnavailable
    }

    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        throw WorldAPIError.databaseUnavailable
    }

    func currentFacts(
        subjectID: EntityID?, predicatePrefix: String?, after: FactID?, limit: Int
    ) async throws -> WorldFactPage {
        throw WorldAPIError.databaseUnavailable
    }

    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    {
        throw WorldAPIError.databaseUnavailable
    }

    func snapshot(limit: Int) async throws -> WorldSnapshot {
        throw WorldAPIError.databaseUnavailable
    }

    func subscribe() async throws -> WorldDeltaStream {
        throw WorldAPIError.databaseUnavailable
    }

    func finishSubscriptions() async {}
}

actor WorldAPIConcurrencyLimiter {
    private let limit: Int
    private var activeRequests = 0

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    func withPermit<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        guard activeRequests < limit else {
            throw WorldAPIError.overloaded(limit: limit)
        }
        activeRequests += 1
        do {
            let value = try await operation()
            activeRequests -= 1
            return value
        } catch {
            activeRequests -= 1
            throw error
        }
    }
}

extension WorldEventDisposition: Codable {}

extension WorldEventAcceptanceResponse {
    init(_ acceptance: WorldEventAcceptance) {
        self.init(disposition: acceptance.disposition, event: acceptance.event)
    }
}
