import Foundation

/// Client-side mirror of the server's storyboard validation caps (server v3.17.0). Keep in sync so
/// the editor blocks an over-cap save before the round-trip instead of surfacing a 400.
public enum StoryboardLimits {
    /// Maximum length, in characters, of a storyboard `title`.
    public static let maxTitle = 256
    /// Maximum length, in characters, of a storyboard's `notes`.
    public static let maxNotes = 16384
    /// Maximum number of tiles on a storyboard.
    public static let maxTiles = 200
    /// Maximum length, in characters, of a tile `label`.
    public static let maxTileLabel = 256
}
