import Foundation
import Testing

@testable import Common

@Suite("RTPRemoteProtocol framing")
struct RTPRemoteProtocolTests {

    @Test("hello encodes with type and channels")
    func helloEncodes() throws {
        let hello = RTPRemoteHello(
            viewerName: "Test Viewer", viewerVersion: "1.2.3", channels: [1, 2, 5])
        let data = try JSONEncoder().encode(hello)
        let decoded = try JSONDecoder().decode(RTPRemoteHello.self, from: data)
        #expect(decoded.type == "hello")
        #expect(decoded.viewerName == "Test Viewer")
        #expect(decoded.viewerVersion == "1.2.3")
        #expect(decoded.channels == [1, 2, 5])
    }

    @Test("frame round-trips through encode and parse")
    func frameRoundTrips() {
        let payload = Data([0x80, 0x60, 0x01, 0x02, 0xDE, 0xAD, 0xBE, 0xEF])
        let frame = RTPRemoteFrame(channel: 7, kind: .rtp, payload: payload)
        let encoded = RTPRemoteStream.encode(frame)
        #expect(encoded != nil)

        var parser = RTPRemoteStream.Parser()
        var frames: [RTPRemoteFrame] = []
        let ok = parser.append(encoded!) { frames.append($0) }
        #expect(ok)
        #expect(frames == [frame])
    }

    @Test("parser reassembles frames split across arbitrary chunk boundaries")
    func parserHandlesFragmentation() {
        let frames = [
            RTPRemoteFrame(channel: 1, kind: .rtp, payload: Data(repeating: 0xAA, count: 37)),
            RTPRemoteFrame(channel: 17, kind: .rtcp, payload: Data(repeating: 0xBB, count: 3)),
            RTPRemoteFrame(channel: 16, kind: .rtp, payload: Data()),
        ]
        var stream = Data()
        for frame in frames {
            stream.append(RTPRemoteStream.encode(frame)!)
        }

        // Feed the byte stream one byte at a time — the cruelest fragmentation TCP can produce.
        var parser = RTPRemoteStream.Parser()
        var parsed: [RTPRemoteFrame] = []
        for byte in stream {
            let ok = parser.append(Data([byte])) { parsed.append($0) }
            #expect(ok)
        }
        #expect(parsed == frames)
    }

    @Test("parser handles multiple frames in one chunk")
    func parserHandlesCoalescing() {
        let frames = (1...16).map {
            RTPRemoteFrame(
                channel: $0, kind: .rtp, payload: Data(repeating: UInt8($0), count: $0 * 10))
        }
        var stream = Data()
        for frame in frames {
            stream.append(RTPRemoteStream.encode(frame)!)
        }

        var parser = RTPRemoteStream.Parser()
        var parsed: [RTPRemoteFrame] = []
        let ok = parser.append(stream) { parsed.append($0) }
        #expect(ok)
        #expect(parsed == frames)
    }

    @Test("oversized frame length poisons the stream")
    func oversizedFrameFails() {
        var parser = RTPRemoteStream.Parser()
        var frames: [RTPRemoteFrame] = []
        // Length prefix far beyond maxFrameLength.
        let ok = parser.append(Data([0xFF, 0xFF, 0x01, 0x00])) { frames.append($0) }
        #expect(!ok)
        #expect(frames.isEmpty)
    }

    @Test("length below header size poisons the stream")
    func undersizedFrameFails() {
        var parser = RTPRemoteStream.Parser()
        var frames: [RTPRemoteFrame] = []
        // Length 1 can't even hold channel + kind.
        let ok = parser.append(Data([0x00, 0x01, 0x05])) { frames.append($0) }
        #expect(!ok)
        #expect(frames.isEmpty)
    }

    @Test("unknown kind byte poisons the stream")
    func unknownKindFails() {
        var parser = RTPRemoteStream.Parser()
        var frames: [RTPRemoteFrame] = []
        let ok = parser.append(Data([0x00, 0x02, 0x03, 0x09])) { frames.append($0) }
        #expect(!ok)
        #expect(frames.isEmpty)
    }

    @Test("encode rejects payloads beyond the ceiling")
    func encodeRejectsOversized() {
        let tooBig = RTPRemoteFrame(
            channel: 1,
            kind: .rtp,
            payload: Data(repeating: 0, count: RTPRemoteStream.maxFrameLength + 1)
        )
        #expect(RTPRemoteStream.encode(tooBig) == nil)
    }

    @Test("empty payload frame round-trips")
    func emptyPayloadRoundTrips() {
        let frame = RTPRemoteFrame(channel: 3, kind: .rtcp, payload: Data())
        var parser = RTPRemoteStream.Parser()
        var frames: [RTPRemoteFrame] = []
        let ok = parser.append(RTPRemoteStream.encode(frame)!) { frames.append($0) }
        #expect(ok)
        #expect(frames == [frame])
    }
}
