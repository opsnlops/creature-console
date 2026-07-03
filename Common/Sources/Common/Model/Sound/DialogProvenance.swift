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

    /// One mouth cue: a mouth shape held over a time span (Rhubarb-style visemes,
    /// derived from the ElevenLabs alignment).
    public struct MouthCue: Sendable, Equatable {
        public let start: Double
        public let end: Double
        public let shape: String

        public init(start: Double, end: Double, shape: String) {
            self.start = start
            self.end = end
            self.shape = shape
        }
    }

    /// The lip-sync for one creature's lane: its mouth cues over time.
    public struct LipsyncTrack: Sendable, Equatable, Identifiable {
        public let channel: Int
        public let name: String
        public let cues: [MouthCue]
        public var id: Int { channel }

        public init(channel: Int, name: String, cues: [MouthCue]) {
            self.channel = channel
            self.name = name
            self.cues = cues
        }
    }

    public let sourceScriptId: String
    public let title: String
    public let generationIds: [String]
    /// The full rendered script, `Speaker: line` per turn, newline-separated.
    public let scriptText: String
    public let tracks: [Track]
    /// Per-creature mouth cues embedded in the file (#53); empty if none.
    public let lipsync: [LipsyncTrack]

    public init(
        sourceScriptId: String, title: String, generationIds: [String], scriptText: String,
        tracks: [Track], lipsync: [LipsyncTrack] = []
    ) {
        self.sourceScriptId = sourceScriptId
        self.title = title
        self.generationIds = generationIds
        self.scriptText = scriptText
        self.tracks = tracks
        self.lipsync = lipsync
    }

    /// The script split into individual turn lines (empty if there's no script).
    public var scriptLines: [String] {
        scriptText.isEmpty ? [] : scriptText.components(separatedBy: "\n")
    }

    /// True when there's anything worth showing.
    public var hasContent: Bool {
        !sourceScriptId.isEmpty || !title.isEmpty || !scriptText.isEmpty || !tracks.isEmpty
            || !lipsync.isEmpty
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
            tracks: DialogProvenance.parseTracks(in: iXML),
            lipsync: DialogProvenance.parseLipsync(in: iXML)
        )
    }

    // MARK: - Minimal iXML extraction
    //
    // The server writes flat, non-nested elements (see IxmlWriter.cpp), so a small
    // substring extractor is enough and avoids a full XML parser.

    static func field(_ tag: String, in xml: String) -> String? {
        rawField(tag, in: xml).map(unescape)
    }

    /// The raw (still-escaped) inner text of the first `<tag>…</tag>`. Used to
    /// scope a scan to one block — `<TRACK>` appears in both TRACK_LIST and
    /// LIPSYNC, so parsers must not scan the whole document.
    static func rawField(_ tag: String, in xml: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = xml.range(of: open),
            let end = xml.range(of: close, range: start.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    static func parseTracks(in xml: String) -> [Track] {
        guard let block = rawField("TRACK_LIST", in: xml) else { return [] }
        var tracks: [Track] = []
        var searchStart = block.startIndex
        while let start = block.range(of: "<TRACK>", range: searchStart..<block.endIndex),
            let end = block.range(of: "</TRACK>", range: start.upperBound..<block.endIndex)
        {
            let entry = String(block[start.upperBound..<end.lowerBound])
            if let channelString = field("CHANNEL_INDEX", in: entry),
                let channel = Int(channelString)
            {
                let name = field("NAME", in: entry) ?? ""
                // A complete poly-WAV TRACK_LIST names every channel and leaves silent
                // lanes blank; only surface the named ones in the UI.
                if !name.isEmpty {
                    tracks.append(Track(channel: channel, name: name))
                }
            }
            searchStart = end.upperBound
        }
        return tracks
    }

    static func parseLipsync(in xml: String) -> [LipsyncTrack] {
        guard let block = rawField("LIPSYNC", in: xml) else { return [] }
        var result: [LipsyncTrack] = []
        var searchStart = block.startIndex
        while let start = block.range(of: "<TRACK>", range: searchStart..<block.endIndex),
            let end = block.range(of: "</TRACK>", range: start.upperBound..<block.endIndex)
        {
            let entry = String(block[start.upperBound..<end.lowerBound])
            if let channelString = field("CHANNEL_INDEX", in: entry),
                let channel = Int(channelString)
            {
                let name = field("NAME", in: entry) ?? ""
                let cues = parseCues(field("CUES", in: entry) ?? "")
                result.append(LipsyncTrack(channel: channel, name: name, cues: cues))
            }
            searchStart = end.upperBound
        }
        return result
    }

    /// Unpack the compact `"start end shape;start end shape;…"` cue encoding.
    static func parseCues(_ packed: String) -> [MouthCue] {
        packed.split(separator: ";").compactMap { part in
            let f = part.split(separator: " ")
            guard f.count == 3, let start = Double(f[0]), let end = Double(f[1]) else { return nil }
            return MouthCue(start: start, end: end, shape: String(f[2]))
        }
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
