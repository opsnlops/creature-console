import Foundation

public struct CreatureRuntimeActivity: Codable, Sendable, Equatable, Hashable {
    public let state: ActivityState
    public let animationId: String?
    public let sessionId: String?
    public let reason: ActivityReason?
    public let startedAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case state
        case animationId = "animation_id"
        case sessionId = "session_id"
        case reason
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }

    public init(
        state: ActivityState,
        animationId: String?,
        sessionId: String?,
        reason: ActivityReason?,
        startedAt: Date?,
        updatedAt: Date?
    ) {
        self.state = state
        self.animationId = animationId
        self.sessionId = sessionId
        self.reason = reason
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

public struct CreatureRuntimeCounters: Codable, Sendable, Equatable, Hashable {
    public let sessionsStartedTotal: UInt64?
    public let sessionsCancelledTotal: UInt64?
    public let idleStartedTotal: UInt64?
    public let idleStoppedTotal: UInt64?
    public let idleTogglesTotal: UInt64?
    public let skipsMissingCreatureTotal: UInt64?
    public let bgmTakeoversTotal: UInt64?
    public let audioResetsTotal: UInt64?

    enum CodingKeys: String, CodingKey {
        case sessionsStartedTotal = "sessions_started_total"
        case sessionsCancelledTotal = "sessions_cancelled_total"
        case idleStartedTotal = "idle_started_total"
        case idleStoppedTotal = "idle_stopped_total"
        case idleTogglesTotal = "idle_toggles_total"
        case skipsMissingCreatureTotal = "skips_missing_creature_total"
        case bgmTakeoversTotal = "bgm_takeovers_total"
        case audioResetsTotal = "audio_resets_total"
    }
}

public struct CreatureRuntimeError: Codable, Sendable, Equatable, Hashable {
    public let message: String
    public let timestamp: Date
}

public struct CreatureRuntime: Codable, Sendable, Equatable, Hashable {
    public let idleEnabled: Bool?
    public let activity: CreatureRuntimeActivity?
    public let counters: CreatureRuntimeCounters?
    public let bgmOwner: String?
    public let lastError: CreatureRuntimeError?

    enum CodingKeys: String, CodingKey {
        case idleEnabled = "idle_enabled"
        case activity
        case counters
        case bgmOwner = "bgm_owner"
        case lastError = "last_error"
    }

    public init(
        idleEnabled: Bool?,
        activity: CreatureRuntimeActivity?,
        counters: CreatureRuntimeCounters?,
        bgmOwner: String?,
        lastError: CreatureRuntimeError?
    ) {
        self.idleEnabled = idleEnabled
        self.activity = activity
        self.counters = counters
        self.bgmOwner = bgmOwner
        self.lastError = lastError
    }
}
