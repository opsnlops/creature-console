import Foundation

/// Request body for `POST /api/v1/fixture/{id}/live` (live slider control).
///
/// `timeoutMs` is **required** and must be in `(0, 600000]`. The server holds the
/// supplied values until the deadline elapses, then blacks out all channels on the
/// fixture. Sending another live call before the deadline extends/replaces the
/// deadline; channels not named in a subsequent call retain their previous value
/// within the same session.
///
/// Live arriving cancels any active pattern hard (no fade-out). While live is in
/// effect, the server refuses new `/trigger` calls and binding-driven pattern starts.
public struct SetFixtureLiveDTO: Codable, Sendable {
    public var values: [FixturePatternValue]
    public var timeoutMs: UInt32

    public init(values: [FixturePatternValue], timeoutMs: UInt32) {
        self.values = values
        self.timeoutMs = timeoutMs
    }

    public enum CodingKeys: String, CodingKey {
        case values
        case timeoutMs = "timeout_ms"
    }
}
