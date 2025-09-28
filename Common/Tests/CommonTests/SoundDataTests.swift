import Foundation
import Testing
@testable import Common

@Suite("SoundData decoding and mapping")
struct SoundDataTests {

    @Test("MouthCue.intValue maps all known visemes and defaults correctly")
    func mouthCueIntValueMapping() throws {
        let cases: [(String, UInt8)] = [
            ("A", 5),
            ("B", 180),
            ("C", 240),
            ("D", 255),
            ("E", 50),
            ("F", 20),
            ("X", 0),
            ("?", 5) // default
        ]
        for (symbol, expected) in cases {
            let cue = SoundData.MouthCue(start: 0.0, end: 0.1, value: symbol)
            #expect(cue.intValue == expected, "\(symbol) should map to \(expected)")
        }
    }

    @Test("Decoding full SoundData JSON yields expected structure")
    func soundDataJSONDecoding() throws {
        let json = """
        {
          "metadata": { "soundFile": "foo.flac", "duration": 1.23 },
          "mouthCues": [
            { "start": 0.0, "end": 0.2, "value": "A" },
            { "start": 0.2, "end": 0.4, "value": "B" },
            { "start": 0.4, "end": 0.6, "value": "X" }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SoundData.self, from: json)
        #expect(decoded.metadata.soundFile == "foo.flac")
        #expect(abs(decoded.metadata.duration - 1.23) < 0.0001)
        #expect(decoded.mouthCues.count == 3)
        #expect(decoded.mouthCues[0].value == "A")
        #expect(decoded.mouthCues[1].value == "B")
        #expect(decoded.mouthCues[2].value == "X")
    }

    @Test("MouthCue Codable round-trip preserves fields")
    func mouthCueCodableRoundTrip() throws {
        let original = SoundData.MouthCue(start: 0.25, end: 0.55, value: "E")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SoundData.MouthCue.self, from: data)
        #expect(decoded.start == original.start)
        #expect(decoded.end == original.end)
        #expect(decoded.value == original.value)
        #expect(decoded.intValue == original.intValue)
    }
}

