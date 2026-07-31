import Foundation
import Testing

@testable import Common

@Suite("RTP audio protocol")
struct RTPAudioProtocolTests {
    @Test("Parses fixed RTP header and payload")
    func parsesFixedRTPHeaderAndPayload() {
        let packet = OpusRTPParser.parse(Data(makeRTPPacket()))

        #expect(packet?.sequenceNumber == 0x1234)
        #expect(packet?.timestamp == 0x0102_0304)
        #expect(packet?.synchronizationSource == 0x1020_3040)
        #expect(packet?.payload == Data([0xAA, 0xBB]))
    }

    @Test("Skips RTP contributing sources and header extensions")
    func skipsRTPContributingSourcesAndExtensions() {
        var bytes = makeRTPPacket(firstByte: 0x91)
        bytes.insert(contentsOf: [0x55, 0x66, 0x77, 0x88], at: 12)
        bytes.insert(contentsOf: [0xBE, 0xDE, 0x00, 0x01], at: 16)
        bytes.insert(contentsOf: [0x11, 0x22, 0x33, 0x44], at: 20)

        #expect(OpusRTPParser.parse(Data(bytes))?.payload == Data([0xAA, 0xBB]))
    }

    @Test("Removes RTP padding")
    func removesRTPPadding() {
        var bytes = makeRTPPacket(firstByte: 0xA0)
        bytes.append(contentsOf: [0, 2])

        #expect(OpusRTPParser.parse(Data(bytes))?.payload == Data([0xAA, 0xBB]))
    }

    @Test("Rejects malformed RTP packets")
    func rejectsMalformedRTPPackets() {
        #expect(OpusRTPParser.parse(Data([0x80, RTPAudioConstants.opusPayloadType, 0])) == nil)
        #expect(OpusRTPParser.parse(Data(makeRTPPacket(firstByte: 0x40))) == nil)
        #expect(
            OpusRTPParser.parse(
                Data(makeRTPPacket(payloadType: RTPAudioConstants.opusPayloadType + 1))
            ) == nil
        )
        #expect(OpusRTPParser.parse(Data(makeRTPPacket(firstByte: 0x90))) == nil)

        var invalidPadding = makeRTPPacket(firstByte: 0xA0)
        invalidPadding[invalidPadding.count - 1] = 0x7F
        #expect(OpusRTPParser.parse(Data(invalidPadding)) == nil)
    }

    @Test("Parses RTCP sender report and CNAME")
    func parsesRTCPSenderReportAndCanonicalName() {
        let report = RTCPSenderReportParser.parse(Data(makeServerCompoundPacket()))

        #expect(report?.synchronizationSource == 0x0102_0304)
        #expect(report?.ntpTimestamp == 0x1122_3344_5566_7788)
        #expect(report?.rtpTimestamp == 0x99AA_BBCC)
        #expect(report?.packetCount == 123)
        #expect(report?.octetCount == 45_678)
        #expect(report?.canonicalName == "creature-server@test")
    }

    @Test("Safely skips unknown RTCP compound blocks")
    func skipsUnknownRTCPBlocks() {
        let packet = makeServerCompoundPacket()
        var withUnknown = Array(packet[..<28])
        withUnknown.append(contentsOf: [0x80, 204, 0x00, 0x01, 0x12, 0x34, 0x56, 0x78])
        withUnknown.append(contentsOf: packet[28...])

        #expect(
            RTCPSenderReportParser.parse(Data(withUnknown))?.synchronizationSource
                == 0x0102_0304
        )
    }

    @Test("Rejects malformed RTCP compound packets")
    func rejectsMalformedRTCPPackets() {
        var truncated = makeServerCompoundPacket()
        truncated.removeLast()
        #expect(RTCPSenderReportParser.parse(Data(truncated)) == nil)

        var invalidVersion = makeServerCompoundPacket()
        invalidVersion[0] = 0x40
        #expect(RTCPSenderReportParser.parse(Data(invalidVersion)) == nil)

        var missingCanonicalName = makeServerCompoundPacket()
        missingCanonicalName[36] = 2
        #expect(RTCPSenderReportParser.parse(Data(missingCanonicalName)) == nil)

        #expect(RTCPSenderReportParser.parse(Data(makeServerCompoundPacket(source: 0))) == nil)
    }

    @Test("Converts NTP and wrap-safe RTP timestamps")
    func convertsNetworkTimestamps() {
        let epochOffset: UInt64 = 2_208_988_800
        let halfSecondNTP = epochOffset << 32 | 0x8000_0000
        let halfSecond = RTCPAudioTiming.date(forNTPTimestamp: halfSecondNTP)
        #expect(halfSecond?.timeIntervalSince1970 == 0.5)

        #expect(signedRTPTimestampDifference(20, reference: 10) == 10)
        #expect(signedRTPTimestampDifference(10, reference: 20) == -10)
        #expect(signedRTPTimestampDifference(5, reference: UInt32.max - 4) == 10)
    }

    private func makeRTPPacket(
        firstByte: UInt8 = 0x80,
        payloadType: UInt8 = RTPAudioConstants.opusPayloadType
    ) -> [UInt8] {
        [
            firstByte, payloadType, 0x12, 0x34, 0x01, 0x02, 0x03, 0x04, 0x10, 0x20, 0x30,
            0x40, 0xAA, 0xBB,
        ]
    }

    private func makeServerCompoundPacket(
        source: UInt32 = 0x0102_0304,
        canonicalName: String = "creature-server@test"
    ) -> [UInt8] {
        var packet: [UInt8] = [0x80, 200, 0x00, 0x06]
        append(source, to: &packet)
        append(0x1122_3344, to: &packet)
        append(0x5566_7788, to: &packet)
        append(0x99AA_BBCC, to: &packet)
        append(123, to: &packet)
        append(45_678, to: &packet)

        let sourceDescriptionStart = packet.count
        packet.append(contentsOf: [0x81, 202, 0, 0])
        append(source, to: &packet)
        packet.append(1)
        packet.append(UInt8(canonicalName.utf8.count))
        packet.append(contentsOf: canonicalName.utf8)
        packet.append(0)
        while !(packet.count - sourceDescriptionStart).isMultiple(
            of: MemoryLayout<UInt32>.size
        ) {
            packet.append(0)
        }
        let words = (packet.count - sourceDescriptionStart) / MemoryLayout<UInt32>.size
        packet[sourceDescriptionStart + 2] = UInt8((words - 1) >> 8)
        packet[sourceDescriptionStart + 3] = UInt8(words - 1)
        return packet
    }

    private func append(_ value: UInt32, to packet: inout [UInt8]) {
        packet.append(UInt8(truncatingIfNeeded: value >> 24))
        packet.append(UInt8(truncatingIfNeeded: value >> 16))
        packet.append(UInt8(truncatingIfNeeded: value >> 8))
        packet.append(UInt8(truncatingIfNeeded: value))
    }
}

@Suite("RTP audio jitter buffer")
struct RTPAudioJitterBufferTests {
    @Test("orders packets by RTP timestamp")
    func ordersPacketsByTimestamp() {
        var buffer = RTPAudioJitterBuffer()
        let later = packet(timestamp: 1_480)
        let earlier = packet(timestamp: 1_000)

        #expect(buffer.insert(later) == .newSynchronizationSource)
        #expect(buffer.insert(earlier) == .inserted)
        #expect(buffer.earliestTimestamp() == 1_000)
        #expect(buffer.takePacket(at: 1_000) == earlier)
        #expect(buffer.takePacket(at: 1_480) == later)
    }

    @Test("resets when synchronization source changes")
    func resetsForNewSynchronizationSource() {
        var buffer = RTPAudioJitterBuffer()
        _ = buffer.insert(packet(timestamp: 1_000, synchronizationSource: 1))

        let replacement = packet(timestamp: 50, synchronizationSource: 2)
        #expect(buffer.insert(replacement) == .newSynchronizationSource)
        #expect(buffer.packetCount == 1)
        #expect(buffer.earliestTimestamp() == 50)
    }

    @Test("rejects duplicate and late packets")
    func rejectsDuplicateAndLatePackets() {
        var buffer = RTPAudioJitterBuffer()
        let first = packet(timestamp: 1_000)
        _ = buffer.insert(first)

        #expect(buffer.insert(first) == .duplicate)
        #expect(buffer.takePacket(at: 1_000) == first)
        #expect(buffer.insert(packet(timestamp: 520)) == .rejectedLate)
    }

    @Test("orders timestamps across UInt32 wraparound")
    func ordersAcrossTimestampWraparound() {
        var buffer = RTPAudioJitterBuffer()
        let beforeWrap = packet(timestamp: UInt32.max - 239)
        let afterWrap = packet(timestamp: 240)

        _ = buffer.insert(afterWrap)
        _ = buffer.insert(beforeWrap)

        #expect(buffer.earliestTimestamp() == beforeWrap.timestamp)
        #expect(buffer.hasPacket(after: beforeWrap.timestamp))
    }

    private func packet(
        timestamp: UInt32,
        synchronizationSource: UInt32 = 42
    ) -> OpusRTPPacket {
        OpusRTPPacket(
            sequenceNumber: 1,
            timestamp: timestamp,
            synchronizationSource: synchronizationSource,
            payload: Data([1, 2, 3])
        )
    }
}
