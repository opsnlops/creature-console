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
    /// Maximum UTF-8 byte count for a background-music prompt.
    public static let maxMusicPromptBytes = 4100

    // MARK: Music composition plans (server #200, `src/server/voice/MusicTypes.h`)

    /// Longest music-only tail after the dialog, in milliseconds.
    public static let maxMusicDurationExtensionMilliseconds: Int64 = 60_000
    /// The longest piece the server will request, in milliseconds.
    public static let maxMusicLengthMilliseconds: Int64 = 600_000
    /// Sections per composition plan.
    public static let maxMusicPlanChunks = 30
    /// Shortest and longest single section (generation or audio reference), in milliseconds.
    public static let minMusicChunkMilliseconds: Int64 = 3_000
    public static let maxMusicChunkMilliseconds: Int64 = 120_000
    /// Maximum UTF-8 byte count for one section's description.
    public static let maxMusicChunkTextBytes = 6132
    /// Styles per positive or negative list.
    public static let maxMusicStyles = 50
    /// Maximum UTF-8 byte count of one style entry.
    public static let maxMusicStyleBytes = 200
    /// Largest seed ElevenLabs accepts.
    public static let maxMusicSeed: Int64 = 2_147_483_647
    /// Finetune strength range.
    public static let minMusicFinetuneStrength = 0.0
    public static let maxMusicFinetuneStrength = 2.0
}
