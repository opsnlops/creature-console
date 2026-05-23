import Foundation

/// Request body for `POST /api/v1/fixture/{id}/pattern/preview`.
///
/// The body *is* the pattern — the server constructs an ephemeral `FixturePattern`
/// from these fields and hands it to the same runner that handles saved triggers.
/// Nothing is persisted. Same validation as a saved pattern (each `values[].channel`
/// must exist on the fixture; `assigned_universe` required); live control still
/// preempts.
///
/// Used by the editor's Fire buttons so the user can preview unsaved local edits
/// without an upsert round-trip.
public struct PreviewFixturePatternDTO: Codable, Sendable {
    public var values: [FixturePatternValue]
    public var fadeInMs: UInt32
    public var fadeOutMs: UInt32
    public var holdMs: UInt32
    public var stopAfterMs: UInt32?

    public init(
        values: [FixturePatternValue],
        fadeInMs: UInt32 = 0,
        fadeOutMs: UInt32 = 0,
        holdMs: UInt32 = 0,
        stopAfterMs: UInt32? = nil
    ) {
        self.values = values
        self.fadeInMs = fadeInMs
        self.fadeOutMs = fadeOutMs
        self.holdMs = holdMs
        self.stopAfterMs = stopAfterMs
    }

    public enum CodingKeys: String, CodingKey {
        case values
        case fadeInMs = "fade_in_ms"
        case fadeOutMs = "fade_out_ms"
        case holdMs = "hold_ms"
        case stopAfterMs = "stop_after_ms"
    }
}
