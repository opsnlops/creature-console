import Foundation

/// Optional request body for `POST /api/v1/fixture/{id}/pattern/{pid}/trigger`. With no
/// body the pattern runs with its configured fade-in / hold / fade-out and stays held
/// until something else stops it. With `stopAfterMs` (must be in `(0, 600000]`), the
/// server schedules an auto-stop event.
public struct TriggerFixturePatternDTO: Codable, Sendable {
    public var stopAfterMs: UInt32?

    public init(stopAfterMs: UInt32? = nil) {
        self.stopAfterMs = stopAfterMs
    }

    public enum CodingKeys: String, CodingKey {
        case stopAfterMs = "stop_after_ms"
    }
}
