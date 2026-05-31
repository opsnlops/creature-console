import Foundation

/// Client-side mirror of the server's dialog validation limits.
///
/// These constants live in `src/model/DialogScript.h` server-side. Keep them in sync so
/// the editor validates the same way the API does. The caps apply to both the saved-script
/// path and the inline-render path; exceeding them yields a `400` with an
/// "X is N chars; max M" message (or a hard error from the `/validate` endpoint).
public enum DialogLimits {
    /// Maximum number of turns in a single scene.
    public static let maxTurns = 200
    /// Maximum length, in characters, of a single turn's `text`.
    public static let maxTurnText = 4096
    /// Maximum length, in characters, of a script `title`.
    public static let maxTitle = 256
    /// Maximum length, in characters, of a script's `notes`.
    public static let maxNotes = 16384
}
