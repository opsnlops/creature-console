import Foundation

/// The provenance embedded in a permanent dialog WAV (server issue #47): where a
/// `dialog/<uuid>.wav` came from. Parsed from the iXML (BWFXML) document the
/// server returns from `GET /api/v1/sound/provenance/{filename}`.
///
/// A point-in-time snapshot — the script text is what was rendered, even if the
/// source script has since been edited.
public struct DialogProvenance: Sendable, Equatable {

    /// One interleaved lane: which creature (or BGM) sits on which 1-based channel.
    public struct Track: Sendable, Equatable, Identifiable {
        public let channel: Int
        public let name: String
        public var id: Int { channel }

        public init(channel: Int, name: String) {
            self.channel = channel
            self.name = name
        }
    }

    public let sourceScriptId: String
    public let title: String
    public let generationIds: [String]
    /// The full rendered script, `Speaker: line` per turn, newline-separated.
    public let scriptText: String
    public let tracks: [Track]

    public init(
        sourceScriptId: String, title: String, generationIds: [String], scriptText: String,
        tracks: [Track]
    ) {
        self.sourceScriptId = sourceScriptId
        self.title = title
        self.generationIds = generationIds
        self.scriptText = scriptText
        self.tracks = tracks
    }

    /// The script split into individual turn lines (empty if there's no script).
    public var scriptLines: [String] {
        scriptText.isEmpty ? [] : scriptText.components(separatedBy: "\n")
    }

    /// True when there's anything worth showing.
    public var hasContent: Bool {
        !sourceScriptId.isEmpty || !title.isEmpty || !scriptText.isEmpty || !tracks.isEmpty
    }

    /// Parse the iXML document the server embeds. Returns nil if the string isn't
    /// a recognizable BWFXML document.
    public init?(iXML: String) {
        guard iXML.contains("<BWFXML>") else { return nil }
        self.init(
            sourceScriptId: DialogProvenance.field("SOURCE_SCRIPT_ID", in: iXML) ?? "",
            title: DialogProvenance.field("TITLE", in: iXML) ?? "",
            generationIds: (DialogProvenance.field("GENERATION_IDS", in: iXML) ?? "")
                .split(separator: ",").map(String.init),
            scriptText: DialogProvenance.field("DIALOG_SCRIPT", in: iXML) ?? "",
            tracks: DialogProvenance.parseTracks(in: iXML)
        )
    }

    // MARK: - Minimal iXML extraction
    //
    // The server writes flat, non-nested elements (see IxmlWriter.cpp), so a small
    // substring extractor is enough and avoids a full XML parser.

    static func field(_ tag: String, in xml: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = xml.range(of: open),
            let end = xml.range(of: close, range: start.upperBound..<xml.endIndex)
        else { return nil }
        return unescape(String(xml[start.upperBound..<end.lowerBound]))
    }

    static func parseTracks(in xml: String) -> [Track] {
        var tracks: [Track] = []
        var searchStart = xml.startIndex
        while let start = xml.range(of: "<TRACK>", range: searchStart..<xml.endIndex),
            let end = xml.range(of: "</TRACK>", range: start.upperBound..<xml.endIndex)
        {
            let block = String(xml[start.upperBound..<end.lowerBound])
            if let channelString = field("CHANNEL_INDEX", in: block),
                let channel = Int(channelString)
            {
                tracks.append(Track(channel: channel, name: field("NAME", in: block) ?? ""))
            }
            searchStart = end.upperBound
        }
        return tracks
    }

    /// Reverse of the server's xmlEscape. `&amp;` must be undone last so a literal
    /// escaped entity in the source (e.g. `&amp;lt;`) round-trips correctly.
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
