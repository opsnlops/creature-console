import Foundation
import Testing

@testable import Common

@Suite("SoundRendition")
struct SoundRenditionTests {

    @Test("both routes are keyed by the source stem + the rendition extension (honest URLs)")
    func renditionFilename() {
        #expect(
            SoundRendition.mp3.renditionFilename(forSourceBasename: "e7cba8df.wav")
                == "e7cba8df.mp3")
        #expect(
            SoundRendition.ogg.renditionFilename(forSourceBasename: "e7cba8df.wav")
                == "e7cba8df.ogg")
        // No extension on the source → stem is the whole name.
        #expect(SoundRendition.mp3.renditionFilename(forSourceBasename: "beep") == "beep.mp3")
    }

    @Test("path segment: mp3 → mp3, ogg → shareable (legacy route)")
    func pathSegment() {
        #expect(SoundRendition.mp3.pathSegment == "mp3")
        #expect(SoundRendition.ogg.pathSegment == "shareable")
    }

    @Test("raw value round-trips (drives the CLI --format arg)")
    func rawValue() {
        #expect(SoundRendition(rawValue: "mp3") == .mp3)
        #expect(SoundRendition(rawValue: "ogg") == .ogg)
        #expect(SoundRendition.allCases.count == 2)
    }
}
