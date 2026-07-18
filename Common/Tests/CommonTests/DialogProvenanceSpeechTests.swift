import Foundation
import Testing

@testable import Common

@Suite("DialogProvenance speech helpers")
struct DialogProvenanceSpeechTests {

    private func provenance(script: String, lipsync: [DialogProvenance.LipsyncTrack] = [])
        -> DialogProvenance
    {
        DialogProvenance(
            sourceScriptId: "s1", title: "Test", generationIds: [], scriptText: script,
            tracks: [], lipsync: lipsync)
    }

    @Test("parses Speaker: text lines and preserves script order")
    func parsesScriptLines() {
        let p = provenance(
            script: "Beaky: Hello there.\nMango: Why not MongoDB?\nBeaky: Because reasons.")
        let lines = p.parsedScriptLines
        #expect(lines.count == 3)
        #expect(lines[0] == .init(index: 0, speaker: "Beaky", text: "Hello there."))
        #expect(lines[1].speaker == "Mango")
        #expect(lines[2].index == 2)
    }

    @Test("splits on the first colon only, keeping colons in the text")
    func keepsColonsInText() {
        let p = provenance(script: "Beaky: the ratio is 3:1, see?")
        #expect(p.parsedScriptLines.first?.text == "the ratio is 3:1, see?")
    }

    @Test("filters lines by speaker, case-insensitively")
    func filtersBySpeaker() {
        let p = provenance(
            script: "Beaky: One.\nMango: Two.\nbeaky: Three.\nBGM: (music)")
        let beaky = p.lines(forSpeaker: "Beaky")
        #expect(beaky.map(\.text) == ["One.", "Three."])
        #expect(p.lines(forSpeaker: "Mango").count == 1)
        #expect(p.lines(forSpeaker: "Nobody").isEmpty)
    }

    @Test("linesBySpeaker groups by lowercased speaker, matching lines(forSpeaker:)")
    func groupsBySpeaker() {
        let p = provenance(
            script: "Beaky: One.\nMango: Two.\nbeaky: Three.")
        let grouped = p.linesBySpeaker
        #expect(grouped["beaky"]?.map(\.text) == ["One.", "Three."])
        #expect(grouped["mango"]?.map(\.text) == ["Two."])
        #expect(grouped["nobody"] == nil)
        // Grouping and the per-speaker filter agree.
        #expect(grouped["beaky"] == p.lines(forSpeaker: "Beaky"))
    }

    @Test("drops malformed lines (no colon, empty speaker)")
    func dropsMalformed() {
        let p = provenance(script: "Beaky: Fine.\nno colon here\n: orphan text")
        #expect(p.parsedScriptLines.count == 1)
        #expect(p.parsedScriptLines.first?.speaker == "Beaky")
    }

    @Test("empty script yields no lines")
    func emptyScript() {
        #expect(provenance(script: "").parsedScriptLines.isEmpty)
    }

    @Test("mouth shape maps to servo openness; X is silence")
    func opennessMapping() {
        #expect(MouthShape.openness("X") == 0)
        #expect(MouthShape.openness("D") == 255)
        #expect(MouthShape.openness("A") == 5)
        #expect(MouthShape.openness("?") == 5)  // unknown → near-closed fallback
        #expect(MouthShape.isSilent("X"))
        #expect(!MouthShape.isSilent("D"))
    }

    @Test("SoundData cue openness stays in lockstep with the shared mapping")
    func soundDataDelegatesToSharedMapping() {
        for shape in ["A", "B", "C", "D", "E", "F", "X", "Z"] {
            let cue = SoundData.MouthCue(start: 0, end: 1, value: shape)
            #expect(cue.intValue == MouthShape.openness(shape))
        }
    }

    // MARK: - LipsyncTrack

    private func track(_ cues: [(Double, Double, String)]) -> DialogProvenance.LipsyncTrack {
        DialogProvenance.LipsyncTrack(
            channel: 1, name: "Beaky",
            cues: cues.map { .init(start: $0.0, end: $0.1, shape: $0.2) })
    }

    @Test("time span spans first cue start to last cue end")
    func timeSpan() {
        let t = track([(0.0, 0.5, "D"), (0.5, 1.0, "X"), (1.0, 2.25, "B")])
        #expect(t.timeSpan == 0.0...2.25)
        #expect(track([]).timeSpan == nil)
    }

    @Test("shape(at:) finds the covering cue via binary search")
    func shapeAtTime() {
        let t = track([(0.0, 0.5, "D"), (0.5, 1.0, "X"), (1.0, 2.0, "B")])
        #expect(t.shape(at: 0.25) == "D")
        #expect(t.shape(at: 0.5) == "X")  // half-open [start, end): 0.5 belongs to the 2nd cue
        #expect(t.shape(at: 1.99) == "B")
        #expect(t.shape(at: 2.0) == nil)  // past the end
        #expect(t.shape(at: -0.1) == nil)  // before the start
    }

    @Test("cue openness delegates to the shared mapping")
    func cueOpenness() {
        let cue = DialogProvenance.MouthCue(start: 0, end: 1, shape: "C")
        #expect(cue.openness == MouthShape.openness("C"))
    }

    // MARK: - Word alignment (#56)

    @Test("parses the WORD_ALIGNMENT iXML block into per-channel word tracks")
    func parsesWordAlignment() {
        let ixml = """
            <BWFXML><WORD_ALIGNMENT>
            <TRACK><CHANNEL_INDEX>1</CHANNEL_INDEX><NAME>Beaky</NAME><WORDS>0.079 0.199 Hey;3.100 3.300 We&apos;re;3.940 4.460 server-side</WORDS></TRACK>
            <TRACK><CHANNEL_INDEX>2</CHANNEL_INDEX><NAME>Mango</NAME><WORDS>1.900 2.100 What&apos;s;2.340 2.680 Beaky?</WORDS></TRACK>
            </WORD_ALIGNMENT></BWFXML>
            """
        let p = DialogProvenance(iXML: ixml)
        #expect(p != nil)
        #expect(p?.words.count == 2)
        let beaky = p?.words.first { $0.channel == 1 }
        #expect(beaky?.name == "Beaky")
        #expect(beaky?.words.map(\.word) == ["Hey", "We're", "server-side"])  // apostrophe unescaped
        #expect(beaky?.words.first?.start == 0.079)
        #expect(beaky?.words.first?.end == 0.199)
        #expect(p?.words.first { $0.channel == 2 }?.words.map(\.word) == ["What's", "Beaky?"])
    }

    @Test("word(at:) returns the covering word, nil in gaps and out of range")
    func wordAtTime() {
        let track = DialogProvenance.WordTrack(
            channel: 1, name: "Beaky",
            words: [
                .init(start: 0.0, end: 0.2, word: "Hey"),
                .init(start: 0.26, end: 0.66, word: "Mango"),  // gap 0.2–0.26
                .init(start: 3.10, end: 3.30, word: "We're"),
            ])
        #expect(track.word(at: 0.1) == "Hey")
        #expect(track.word(at: 0.2) == nil)  // half-open: 0.2 is past "Hey"
        #expect(track.word(at: 0.23) == nil)  // in the gap between words
        #expect(track.word(at: 0.5) == "Mango")
        #expect(track.word(at: 3.29) == "We're")
        #expect(track.word(at: 5.0) == nil)  // past the end
        #expect(track.word(at: -1.0) == nil)  // before the start
    }

    @Test("renders without word alignment simply carry no word tracks")
    func noWordAlignment() {
        let p = DialogProvenance(iXML: "<BWFXML><TITLE>Old Render</TITLE></BWFXML>")
        #expect(p?.words.isEmpty == true)
    }

    // MARK: - Frame baking

    @Test("bakes cues into per-frame openness at the frame rate")
    func bakesFrames() {
        // 20ms/frame: 1s = 50 frames. D over [0,0.1) → frames 0..<5 at 255; rest closed.
        let frames = MouthShape.bakeFrames(
            [
                TimedMouthValue(start: 0.0, end: 0.1, openness: 255),
                TimedMouthValue(start: 0.2, end: 0.24, openness: 180),
            ],
            millisecondsPerFrame: 20, frameCount: 50)
        #expect(frames.count == 50)
        #expect(frames[0...4].allSatisfy { $0 == 255 })
        #expect(frames[5] == 0)  // gap
        #expect(frames[10...11].allSatisfy { $0 == 180 })
        #expect(frames[49] == 0)
    }

    @Test("bake clamps out-of-range cues and tolerates degenerate inputs")
    func bakeClamps() {
        let frames = MouthShape.bakeFrames(
            [TimedMouthValue(start: -1.0, end: 999.0, openness: 100)],
            millisecondsPerFrame: 20, frameCount: 10)
        #expect(frames.count == 10)
        #expect(frames.allSatisfy { $0 == 100 })  // clamped to fill the whole range

        #expect(MouthShape.bakeFrames([], millisecondsPerFrame: 20, frameCount: 0).isEmpty)
        #expect(
            MouthShape.bakeFrames(
                [TimedMouthValue(start: 0, end: 1, openness: 5)],
                millisecondsPerFrame: 0, frameCount: 5) == [0, 0, 0, 0, 0])
    }

    @Test("a lipsync track bakes frames consistent with the shared bake")
    func lipsyncTrackBake() {
        let t = track([(0.0, 0.1, "D"), (0.1, 0.2, "X")])
        let frames = t.mouthFrames(millisecondsPerFrame: 20, frameCount: 50)
        #expect(frames[0] == 255)  // D
        #expect(frames[7] == 0)  // X (silence)
    }
}
