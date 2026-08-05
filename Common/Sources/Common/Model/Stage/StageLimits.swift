import Foundation

/// Client-side mirror of the server's stage validation caps (server v3.37.0). Keep in sync so the
/// editor blocks an invalid save before the round-trip instead of surfacing a 400.
public enum StageLimits {
    /// Maximum length, in characters, of a stage `title`.
    public static let maxTitle = 256
    /// Maximum length, in characters, of a stage's `notes`.
    public static let maxNotes = 16384
    /// Maximum number of placements on a stage — one per creature audio lane. Lane 17 carries
    /// background music, so it never gets a placement.
    public static let maxPlacements = 16
    /// Half-width of the stage box, in metres. The stage is a 10 m cube centred on the listener;
    /// the server rejects anything outside it as a likely unit mix-up.
    public static let coordinateLimit: Float = 5
    /// Coordinate-frame version this client speaks: listener at the origin facing −Z, metres, Y-up.
    public static let currentVersion = 1
}
