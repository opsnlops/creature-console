import Foundation

/// Wire protocol for the CLI's live-audio relay (`creature-cli network rtp-listen`), the audio
/// twin of `SACNRemoteProtocol`.
///
/// A viewer connects over TCP, sends one newline-terminated JSON `RTPRemoteHello`, and then
/// receives a stream of `RTPRemoteFrame`s — raw, unmodified RTP/RTCP datagrams captured from
/// the animatronic VLAN's multicast groups, each tagged with its audio channel and protocol
/// kind. The relay never decodes or re-times anything: the receiving end's live pipeline
/// (jitter buffer, RTCP playout planning, Opus decode) consumes relayed packets exactly as it
/// consumes local multicast.
public struct RTPRemoteHello: Codable, Sendable {
    public let type: String
    public let viewerName: String
    public let viewerVersion: String
    /// Dialog channels (1–16) the viewer wants. The background-music lane
    /// (`RTPAudioConstants.backgroundMusicChannel`) is always relayed regardless.
    public let channels: [Int]

    public init(viewerName: String, viewerVersion: String, channels: [Int]) {
        self.type = "hello"
        self.viewerName = viewerName
        self.viewerVersion = viewerVersion
        self.channels = channels
    }
}

/// One relayed datagram: which multicast lane it arrived on, whether it's RTP or RTCP, and the
/// untouched packet bytes.
public struct RTPRemoteFrame: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        case rtp = 0
        case rtcp = 1
    }

    public let channel: Int
    public let kind: Kind
    public let payload: Data

    public init(channel: Int, kind: Kind, payload: Data) {
        self.channel = channel
        self.kind = kind
        self.payload = payload
    }
}

public enum RTPRemoteStream {
    /// `[u16 big-endian length][u8 channel][u8 kind][payload]` — length covers channel + kind
    /// + payload, so a frame with an empty payload still has length 2.
    public static let lengthPrefixSize = 2
    public static let headerSize = 2
    /// Generous ceiling: the largest RTP/RTCP datagram the pipeline produces, plus our header.
    public static let maxFrameLength = RTPAudioConstants.maximumPacketSize + headerSize

    /// Encode one frame for the TCP stream.
    public static func encode(_ frame: RTPRemoteFrame) -> Data? {
        let length = frame.payload.count + headerSize
        guard length <= maxFrameLength, (0...255).contains(frame.channel) else {
            return nil
        }
        var data = Data(capacity: lengthPrefixSize + length)
        data.append(UInt8((length >> 8) & 0xFF))
        data.append(UInt8(length & 0xFF))
        data.append(UInt8(frame.channel))
        data.append(frame.kind.rawValue)
        data.append(frame.payload)
        return data
    }

    /// Incremental parser for the viewer side: feed it TCP bytes as they arrive, take complete
    /// frames out. A malformed stream (oversized or truncated-header frame) is unrecoverable —
    /// `append` returns `false` and the connection should be dropped.
    public struct Parser: Sendable {
        private var buffer = Data()

        public init() {}

        public mutating func append(_ data: Data, onFrame: (RTPRemoteFrame) -> Void) -> Bool {
            buffer.append(data)
            while buffer.count >= RTPRemoteStream.lengthPrefixSize {
                let length =
                    Int(buffer[buffer.startIndex]) << 8
                    | Int(buffer[buffer.index(after: buffer.startIndex)])
                guard length >= RTPRemoteStream.headerSize,
                    length <= RTPRemoteStream.maxFrameLength
                else {
                    buffer.removeAll(keepingCapacity: false)
                    return false
                }
                let frameEnd = RTPRemoteStream.lengthPrefixSize + length
                guard buffer.count >= frameEnd else {
                    break
                }
                let start = buffer.startIndex
                let channel = Int(buffer[buffer.index(start, offsetBy: 2)])
                let kindByte = buffer[buffer.index(start, offsetBy: 3)]
                let payload = Data(
                    buffer[
                        buffer.index(start, offsetBy: 4)..<buffer.index(start, offsetBy: frameEnd)
                    ])
                buffer.removeSubrange(start..<buffer.index(start, offsetBy: frameEnd))
                guard let kind = RTPRemoteFrame.Kind(rawValue: kindByte) else {
                    buffer.removeAll(keepingCapacity: false)
                    return false
                }
                onFrame(RTPRemoteFrame(channel: channel, kind: kind, payload: payload))
            }
            return true
        }
    }
}
