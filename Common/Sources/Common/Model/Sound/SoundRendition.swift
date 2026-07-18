import Foundation

/// A downmixed, encoded rendition of a stored sound. The format is a first-class value so the
/// URL/download APIs take it as a parameter rather than exposing a method per format — and so the
/// two routes' per-format quirks live in exactly one place.
public enum SoundRendition: String, Sendable, CaseIterable {
    /// MP3 — plays natively in AVFoundation and inline in Slack; the GUI's share/play format.
    case mp3
    /// Ogg/Opus — smaller, but only downloaded (no native player); kept for the CLI.
    case ogg

    /// The REST path segment under `/sound/` that serves this rendition. (The Ogg rendition
    /// predates the naming convention and is served at `/sound/shareable/`.)
    public var pathSegment: String {
        switch self {
        case .mp3: return "mp3"
        case .ogg: return "shareable"
        }
    }

    /// The file extension for a saved rendition.
    public var fileExtension: String { rawValue }

    /// The rendition's filename for a source whose basename is `basename`: `{stem}.{ext}`. Both
    /// routes are keyed by the source **stem** + the rendition extension — the server strips it and
    /// resolves `{stem}.wav` — so the URL is honest (last segment matches the body) and
    /// hard-cacheable (creature-server#57). Doubles as the friendly save-as filename.
    public func renditionFilename(forSourceBasename basename: String) -> String {
        Self.stem(of: basename) + "." + fileExtension
    }

    private static func stem(of basename: String) -> String {
        basename.lastIndex(of: ".").map { String(basename[..<$0]) } ?? basename
    }
}
