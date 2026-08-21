/// The audio formats a streamed ad-hoc exchange can be downloaded as.
///
/// The format is a parameter — one path, one method — not a method per format
/// (the `SoundRendition` rule). This is its own enum rather than a
/// `SoundRendition` extension because exchange routes are addressed by session
/// id (`…/exchange/{sessionId}/audio.mp3`), not rendition path segments, and
/// exchanges also offer the raw stitched WAV.
public enum ExchangeAudioFormat: String, Codable, Sendable, CaseIterable {
    case mp3
    case ogg
    case wav

    public var fileExtension: String { rawValue }

    /// The final path component of the exchange audio route.
    public var routeFilename: String { "audio." + rawValue }

    /// Fallback download filename when the server sends no `Content-Disposition`.
    public func filename(forSessionId sessionId: String) -> String {
        sessionId + "." + fileExtension
    }
}
