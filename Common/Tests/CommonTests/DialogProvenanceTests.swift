import Foundation
import Testing

@testable import Common

@Suite("DialogProvenance iXML parsing")
struct DialogProvenanceTests {

    /// The exact shape IxmlWriter.cpp emits on the server.
    static let sampleIxml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <BWFXML>
          <IXML_VERSION>1.5</IXML_VERSION>
          <PROJECT>creature-server</PROJECT>
          <NOTE>Dialog render: Web Scale</NOTE>
          <TRACK_LIST>
            <TRACK_COUNT>3</TRACK_COUNT>
            <TRACK><CHANNEL_INDEX>1</CHANNEL_INDEX><NAME>Beaky</NAME><INTERLEAVE_INDEX>1</INTERLEAVE_INDEX></TRACK>
            <TRACK><CHANNEL_INDEX>2</CHANNEL_INDEX><NAME>Pip</NAME><INTERLEAVE_INDEX>2</INTERLEAVE_INDEX></TRACK>
            <TRACK><CHANNEL_INDEX>17</CHANNEL_INDEX><NAME>BGM</NAME><INTERLEAVE_INDEX>17</INTERLEAVE_INDEX></TRACK>
          </TRACK_LIST>
          <USER>
            <SOURCE_SCRIPT_ID>script-123</SOURCE_SCRIPT_ID>
            <TITLE>Web Scale</TITLE>
            <GENERATION_IDS>gen-1,gen-2</GENERATION_IDS>
            <DIALOG_SCRIPT>Beaky: Mongo &amp; &quot;friends&quot;
        Pip: web scale!</DIALOG_SCRIPT>
            <LIPSYNC>
              <TRACK><CHANNEL_INDEX>1</CHANNEL_INDEX><NAME>Beaky</NAME><CUES>0.000 0.120 B;0.120 0.250 A;0.250 0.400 X</CUES></TRACK>
              <TRACK><CHANNEL_INDEX>2</CHANNEL_INDEX><NAME>Pip</NAME><CUES>0.000 0.300 C</CUES></TRACK>
            </LIPSYNC>
          </USER>
        </BWFXML>
        """

    @Test("parses all fields from a real document")
    func parsesAllFields() throws {
        let p = try #require(DialogProvenance(iXML: Self.sampleIxml))
        #expect(p.sourceScriptId == "script-123")
        #expect(p.title == "Web Scale")
        #expect(p.generationIds == ["gen-1", "gen-2"])
        #expect(p.hasContent)
    }

    @Test("unescapes and splits the script into turn lines")
    func parsesScript() throws {
        let p = try #require(DialogProvenance(iXML: Self.sampleIxml))
        #expect(p.scriptLines.count == 2)
        #expect(p.scriptLines[0] == "Beaky: Mongo & \"friends\"")
        #expect(p.scriptLines[1] == "Pip: web scale!")
    }

    @Test("parses the track list with channels in order")
    func parsesTracks() throws {
        let p = try #require(DialogProvenance(iXML: Self.sampleIxml))
        // Scoped to TRACK_LIST — the LIPSYNC block also uses <TRACK> but must not leak in.
        #expect(p.tracks.count == 3)
        #expect(p.tracks.map(\.channel) == [1, 2, 17])
        #expect(p.tracks.map(\.name) == ["Beaky", "Pip", "BGM"])
    }

    @Test("parses per-creature lip-sync mouth cues")
    func parsesLipsync() throws {
        let p = try #require(DialogProvenance(iXML: Self.sampleIxml))
        #expect(p.lipsync.count == 2)

        let beaky = try #require(p.lipsync.first { $0.name == "Beaky" })
        #expect(beaky.channel == 1)
        #expect(beaky.cues.count == 3)
        #expect(beaky.cues[0] == .init(start: 0.0, end: 0.12, shape: "B"))
        #expect(beaky.cues[2] == .init(start: 0.25, end: 0.40, shape: "X"))

        let pip = try #require(p.lipsync.first { $0.name == "Pip" })
        #expect(pip.cues == [.init(start: 0.0, end: 0.3, shape: "C")])
    }

    @Test("no lip-sync when the document has none")
    func noLipsync() throws {
        let xml = "<BWFXML><USER><DIALOG_SCRIPT>Beaky: hi</DIALOG_SCRIPT></USER></BWFXML>"
        let p = try #require(DialogProvenance(iXML: xml))
        #expect(p.lipsync.isEmpty)
    }

    @Test("skips silent (blank-name) lanes from a complete poly track list")
    func skipsBlankTrackNames() throws {
        // A full 17-channel export names every lane, silent ones blank.
        let xml = """
            <BWFXML>
              <TRACK_LIST>
                <TRACK_COUNT>4</TRACK_COUNT>
                <TRACK><CHANNEL_INDEX>1</CHANNEL_INDEX><NAME>Beaky</NAME><INTERLEAVE_INDEX>1</INTERLEAVE_INDEX></TRACK>
                <TRACK><CHANNEL_INDEX>2</CHANNEL_INDEX><NAME></NAME><INTERLEAVE_INDEX>2</INTERLEAVE_INDEX></TRACK>
                <TRACK><CHANNEL_INDEX>3</CHANNEL_INDEX><NAME></NAME><INTERLEAVE_INDEX>3</INTERLEAVE_INDEX></TRACK>
                <TRACK><CHANNEL_INDEX>17</CHANNEL_INDEX><NAME>BGM</NAME><INTERLEAVE_INDEX>17</INTERLEAVE_INDEX></TRACK>
              </TRACK_LIST>
              <USER><DIALOG_SCRIPT></DIALOG_SCRIPT></USER>
            </BWFXML>
            """
        let p = try #require(DialogProvenance(iXML: xml))
        #expect(p.tracks.map(\.name) == ["Beaky", "BGM"])
        #expect(p.tracks.map(\.channel) == [1, 17])
    }

    @Test("returns nil for a non-BWFXML string")
    func rejectsNonBwfxml() {
        #expect(DialogProvenance(iXML: "not xml at all") == nil)
        #expect(DialogProvenance(iXML: "<html><body>nope</body></html>") == nil)
    }

    @Test("tolerates a document with an empty script and no tracks")
    func handlesMinimalDocument() throws {
        let xml = """
            <BWFXML>
              <USER>
                <SOURCE_SCRIPT_ID></SOURCE_SCRIPT_ID>
                <TITLE></TITLE>
                <GENERATION_IDS></GENERATION_IDS>
                <DIALOG_SCRIPT></DIALOG_SCRIPT>
              </USER>
            </BWFXML>
            """
        let p = try #require(DialogProvenance(iXML: xml))
        #expect(p.scriptLines.isEmpty)
        #expect(p.tracks.isEmpty)
        #expect(p.generationIds.isEmpty)
        #expect(!p.hasContent)
    }
}
