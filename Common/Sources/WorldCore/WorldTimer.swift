import Foundation

public enum WorldTimerStatus: String, Hashable, Sendable, Codable {
    case pending
    case firing
    case fired
    case canceled
}

public struct WorldTimer: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var timerID: TimerID
    public var purpose: WorldEventType
    public var dueAt: Date
    public var status: WorldTimerStatus
    public var firingAt: Date?
    public var firedAt: Date?
    public var canceledAt: Date?
    public var subjectIDs: [EntityID]
    public var causedBy: [ProvenanceReference]
    public var payload: [String: WorldJSONValue]

    public init(
        timerID: TimerID,
        purpose: WorldEventType,
        dueAt: Date,
        status: WorldTimerStatus = .pending,
        firingAt: Date? = nil,
        firedAt: Date? = nil,
        canceledAt: Date? = nil,
        subjectIDs: [EntityID],
        causedBy: [ProvenanceReference],
        payload: [String: WorldJSONValue]
    ) {
        self.schemaVersion = WorldSchema.currentVersion
        self.timerID = timerID
        self.purpose = purpose
        self.dueAt = dueAt
        self.status = status
        self.firingAt = firingAt
        self.firedAt = firedAt
        self.canceledAt = canceledAt
        self.subjectIDs = subjectIDs
        self.causedBy = causedBy
        self.payload = payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        self.schemaVersion = schemaVersion
        self.timerID = try container.decode(TimerID.self, forKey: .timerID)
        self.purpose = try container.decode(WorldEventType.self, forKey: .purpose)
        self.dueAt = try container.decode(Date.self, forKey: .dueAt)
        self.status = try container.decode(WorldTimerStatus.self, forKey: .status)
        self.firingAt = try container.decodeIfPresent(Date.self, forKey: .firingAt)
        self.firedAt = try container.decodeIfPresent(Date.self, forKey: .firedAt)
        self.canceledAt = try container.decodeIfPresent(Date.self, forKey: .canceledAt)
        self.subjectIDs = try container.decode([EntityID].self, forKey: .subjectIDs)
        self.causedBy = try container.decode(
            [ProvenanceReference].self,
            forKey: .causedBy
        )
        self.payload = try container.decode([String: WorldJSONValue].self, forKey: .payload)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case timerID = "timer_id"
        case purpose
        case dueAt = "due_at"
        case status
        case firingAt = "firing_at"
        case firedAt = "fired_at"
        case canceledAt = "canceled_at"
        case subjectIDs = "subject_ids"
        case causedBy = "caused_by"
        case payload
    }
}
