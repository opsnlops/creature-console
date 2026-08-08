import Foundation

/// One animation that was rendered against a stage.
public struct StageAnimationReference: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var animationID: AnimationIdentifier
    public var title: String
    public var sourceScriptID: String
    /// The stage's `updated_at` at the moment this animation was rendered.
    public var sourceStageUpdatedAt: Int64
    /// `true` when the stage has been edited since this animation was rendered.
    public var isStale: Bool

    public var id: AnimationIdentifier { animationID }

    enum CodingKeys: String, CodingKey {
        case animationID = "animation_id"
        case title
        case sourceScriptID = "source_script_id"
        case sourceStageUpdatedAt = "source_stage_updated_at"
        case isStale = "stale"
    }

    public var sourceStageUpdatedAtDate: Date {
        Date(timeIntervalSince1970: Double(sourceStageUpdatedAt) / 1000.0)
    }
}

/// Response body for `GET /api/v1/stage/{id}/animations`, most out-of-date first.
///
/// An animation is stale when it was rendered against an older version of the stage than the one
/// stored now — move a creature and everything built on that stage is stale until re-rendered.
public struct StageAnimationsDTO: Codable, Equatable, Sendable {

    public var count: Int32
    public var staleCount: Int32
    /// The stage's current `updated_at`, which staleness is measured against.
    public var stageUpdatedAt: Int64
    public var items: [StageAnimationReference]

    enum CodingKeys: String, CodingKey {
        case count
        case staleCount = "stale_count"
        case stageUpdatedAt = "stage_updated_at"
        case items
    }

    /// A short summary for the stage editor, or `nil` when nothing is out of date.
    public var stalenessSummary: String? {
        guard staleCount > 0 else { return nil }
        return "\(staleCount) of \(count) animations out of date"
    }
}
