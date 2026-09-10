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

struct WorldEventPage: Codable, Equatable, Sendable {
    let events: [WorldEventEnvelope]
    let nextSequence: Int64
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case events
        case nextSequence = "next_sequence"
        case hasMore = "has_more"
    }
}

struct WorldFactPage: Codable, Equatable, Sendable {
    let facts: [Fact]
    let nextFactID: FactID?
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case facts
        case nextFactID = "next_fact_id"
        case hasMore = "has_more"
    }
}

struct WorldTimerPage: Codable, Equatable, Sendable {
    let timers: [WorldTimer]
    let nextTimerID: TimerID?
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case timers
        case nextTimerID = "next_timer_id"
        case hasMore = "has_more"
    }
}

struct WorldSnapshot: Codable, Equatable, Sendable {
    let latestSequence: Int64
    let facts: [Fact]
    let timers: [WorldTimer]
    let factsTruncated: Bool
    let timersTruncated: Bool

    private enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case facts
        case timers
        case factsTruncated = "facts_truncated"
        case timersTruncated = "timers_truncated"
    }
}

struct WorldAPIErrorResponse: Codable, Equatable, Sendable {
    let error: String
    let message: String
}

protocol WorldApplicationService: Sendable {
    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance
    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage
    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int) async throws
        -> WorldFactPage
    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    func snapshot(limit: Int) async throws -> WorldSnapshot
    func subscribe() async throws -> WorldDeltaStream
    func finishSubscriptions() async
}

protocol ConversationApplicationService: Sendable {
    func ingest(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult
    func conversationItems(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage
    func subscribe(to conversationID: ConversationID) async throws -> ConversationItemStream
    func finishConversationSubscriptions() async
}

struct UnavailableConversationApplicationService: ConversationApplicationService {
    func ingest(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult {
        throw WorldAPIError.databaseUnavailable
    }

    func conversationItems(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage {
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

    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int) async throws
        -> WorldFactPage
    {
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
