import Foundation

/// Console-owned spatial-audio mix settings carried on a stage.
///
/// The server stores and returns this block verbatim and never looks inside it — it exists here so
/// the spatial renderer and the server's head aiming read one document instead of two that drift.
public struct StageAudioSettings: Codable, Equatable, Hashable, Sendable {

    public var monitoringDelayMilliseconds: Int
    public var commonPlayoutDelayMilliseconds: Int
    public var backgroundMusicGain: Float
    public var reverbBlend: Float

    /// Keys written by a newer client that this one doesn't model, preserved across round-trips.
    public var additionalFields: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case monitoringDelayMilliseconds = "monitoring_delay_ms"
        case commonPlayoutDelayMilliseconds = "common_playout_delay_ms"
        case backgroundMusicGain = "background_music_gain"
        case reverbBlend = "reverb_blend"
    }

    public init(
        monitoringDelayMilliseconds: Int = 10,
        commonPlayoutDelayMilliseconds: Int = 20,
        backgroundMusicGain: Float = 0.7,
        reverbBlend: Float = 0.08,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.monitoringDelayMilliseconds = monitoringDelayMilliseconds
        self.commonPlayoutDelayMilliseconds = commonPlayoutDelayMilliseconds
        self.backgroundMusicGain = backgroundMusicGain
        self.reverbBlend = reverbBlend
        self.additionalFields = additionalFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitoringDelayMilliseconds =
            try container.decodeIfPresent(Int.self, forKey: .monitoringDelayMilliseconds) ?? 10
        commonPlayoutDelayMilliseconds =
            try container.decodeIfPresent(Int.self, forKey: .commonPlayoutDelayMilliseconds) ?? 20
        backgroundMusicGain =
            try container.decodeIfPresent(Float.self, forKey: .backgroundMusicGain) ?? 0.7
        reverbBlend = try container.decodeIfPresent(Float.self, forKey: .reverbBlend) ?? 0.08

        let everything =
            (try? decoder.singleValueContainer().decode([String: JSONValue].self)) ?? [:]
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        additionalFields = everything.filter { !known.contains($0.key) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(monitoringDelayMilliseconds, forKey: .monitoringDelayMilliseconds)
        try container.encode(
            commonPlayoutDelayMilliseconds, forKey: .commonPlayoutDelayMilliseconds)
        try container.encode(backgroundMusicGain, forKey: .backgroundMusicGain)
        try container.encode(reverbBlend, forKey: .reverbBlend)

        guard !additionalFields.isEmpty else { return }
        var passthrough = encoder.container(keyedBy: JSONCodingKey.self)
        for (key, value) in additionalFields {
            guard let codingKey = JSONCodingKey(stringValue: key) else { continue }
            try passthrough.encode(value, forKey: codingKey)
        }
    }
}

extension StageAudioSettings.CodingKeys: CaseIterable {}

/// A saved stage: where each creature physically sits and which way it faces.
///
/// Mirrors `Storyboard` — `id`/`createdAt`/`updatedAt` are server-managed and timestamps are int64
/// epoch milliseconds (decoder-strategy independent).
///
/// **IMPORTANT**: keep in sync with `StageModel` in the GUI package.
public struct Stage: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: StageIdentifier
    public var title: String
    public var notes: String
    /// Coordinate-frame version. `1` = listener at the origin facing −Z, metres, Y-up. The server
    /// refuses a version it doesn't understand.
    public var version: Int
    public var placements: [StagePlacement]
    public var audio: StageAudioSettings
    public var createdAt: Int64?
    public var updatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case version
        case placements
        case audio
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: StageIdentifier,
        title: String,
        notes: String = "",
        version: Int = StageLimits.currentVersion,
        placements: [StagePlacement] = [],
        audio: StageAudioSettings = StageAudioSettings(),
        createdAt: Int64? = nil,
        updatedAt: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.version = version
        self.placements = placements
        self.audio = audio
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(StageIdentifier.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        version =
            try container.decodeIfPresent(Int.self, forKey: .version) ?? StageLimits.currentVersion
        placements =
            try container.decodeIfPresent([StagePlacement].self, forKey: .placements) ?? []
        audio =
            try container.decodeIfPresent(StageAudioSettings.self, forKey: .audio)
            ?? StageAudioSettings()
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Emit the id as a lowercase UUID string — the server matches ids case-sensitively.
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(version, forKey: .version)
        try container.encode(placements, forKey: .placements)
        try container.encode(audio, forKey: .audio)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public var createdAtDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
    public var updatedAtDate: Date? {
        updatedAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }

    public func placement(for creatureID: CreatureIdentifier) -> StagePlacement? {
        placements.first { $0.creatureID == creatureID }
    }
}

/// Wire body for `POST`/`PUT /api/v1/stage[/{id}]` — only the editable fields. The server stamps and
/// owns `id`/`created_at`/`updated_at`; the `id` for a `PUT` travels in the URL path.
public struct UpsertStageRequest: Encodable, Sendable {

    public var title: String
    public var notes: String
    public var version: Int
    public var placements: [StagePlacement]
    public var audio: StageAudioSettings

    enum CodingKeys: String, CodingKey {
        case title, notes, version, placements, audio
    }

    public init(
        title: String,
        notes: String,
        version: Int = StageLimits.currentVersion,
        placements: [StagePlacement],
        audio: StageAudioSettings
    ) {
        self.title = title
        self.notes = notes
        self.version = version
        self.placements = placements
        self.audio = audio
    }

    public init(_ stage: Stage) {
        self.init(
            title: stage.title, notes: stage.notes, version: stage.version,
            placements: stage.placements, audio: stage.audio)
    }
}

extension Stage {

    /// A fresh, empty stage with a client-side UUID `id` (the server stamps its own on create).
    public static func newEmpty(title: String = "") -> Stage {
        Stage(id: UUID(), title: title)
    }

    public static func mock() -> Stage {
        Stage(
            id: UUID(),
            title: "Mainstage",
            notes: "Beaky on the tall perch, Mango low and to the right.",
            placements: [
                StagePlacement(
                    creatureID: "4754fc0e-1706-11ef-931d-bbb95a696e2e", creatureName: "Beaky",
                    audioChannel: 1, x: -1.2, y: 0.10, z: -3.0, yaw: 35),
                StagePlacement(
                    creatureID: "e93b9a7a-1704-11ef-84b9-3b37dddeb225", creatureName: "Mango",
                    audioChannel: 2, x: 1.2, y: -0.35, z: -2.8, yaw: -20),
            ],
            createdAt: 1_748_579_999_000,
            updatedAt: 1_748_580_015_000
        )
    }
}
