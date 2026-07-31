import Foundation

public enum RTPAudioConstants {
    public static let dialogMulticastPrefix = "239.19.63."
    public static let backgroundMusicMulticastAddress = "239.19.63.17"
    public static let rtpPort: UInt16 = 5004
    public static let rtcpPort: UInt16 = 5005
    public static let opusPayloadType: UInt8 = 96
    public static let sampleRate: UInt32 = 48_000
    public static let packetDurationMilliseconds: UInt32 = 10
    public static let framesPerPacket: UInt32 = 480
    public static let maximumPacketSize = 2_048

    public static func dialogMulticastAddress(channel: Int) -> String? {
        guard (1...16).contains(channel) else {
            return nil
        }
        return dialogMulticastPrefix + String(channel)
    }
}

public struct OpusRTPPacket: Equatable, Sendable {
    public let sequenceNumber: UInt16
    public let timestamp: UInt32
    public let synchronizationSource: UInt32
    public let payload: Data

    public init(
        sequenceNumber: UInt16,
        timestamp: UInt32,
        synchronizationSource: UInt32,
        payload: Data
    ) {
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.synchronizationSource = synchronizationSource
        self.payload = payload
    }
}

public enum OpusRTPParser {
    public static func parse(_ data: Data) -> OpusRTPPacket? {
        let bytes = [UInt8](data)
        let fixedHeaderSize = 12
        guard bytes.count >= fixedHeaderSize, bytes[0] >> 6 == 2 else {
            return nil
        }

        let hasPadding = bytes[0] & 0x20 != 0
        let hasExtension = bytes[0] & 0x10 != 0
        let contributingSourceCount = Int(bytes[0] & 0x0F)
        guard bytes[1] & 0x7F == RTPAudioConstants.opusPayloadType else {
            return nil
        }

        var payloadOffset = fixedHeaderSize + contributingSourceCount * MemoryLayout<UInt32>.size
        guard payloadOffset <= bytes.count else {
            return nil
        }

        if hasExtension {
            let extensionHeaderSize = 4
            guard payloadOffset + extensionHeaderSize <= bytes.count else {
                return nil
            }
            let extensionWords = Int(readUInt16(bytes, at: payloadOffset + 2))
            let extensionSize = extensionHeaderSize + extensionWords * MemoryLayout<UInt32>.size
            guard payloadOffset + extensionSize <= bytes.count else {
                return nil
            }
            payloadOffset += extensionSize
        }

        var payloadEnd = bytes.count
        if hasPadding {
            guard let paddingByte = bytes.last else {
                return nil
            }
            let paddingCount = Int(paddingByte)
            guard paddingCount > 0, paddingCount <= payloadEnd - payloadOffset else {
                return nil
            }
            payloadEnd -= paddingCount
        }

        guard payloadOffset < payloadEnd else {
            return nil
        }

        return OpusRTPPacket(
            sequenceNumber: readUInt16(bytes, at: 2),
            timestamp: readUInt32(bytes, at: 4),
            synchronizationSource: readUInt32(bytes, at: 8),
            payload: Data(bytes[payloadOffset..<payloadEnd])
        )
    }
}

public struct RTCPSenderReport: Equatable, Sendable {
    public let synchronizationSource: UInt32
    public let ntpTimestamp: UInt64
    public let rtpTimestamp: UInt32
    public let packetCount: UInt32
    public let octetCount: UInt32
    public let canonicalName: String

    public init(
        synchronizationSource: UInt32,
        ntpTimestamp: UInt64,
        rtpTimestamp: UInt32,
        packetCount: UInt32,
        octetCount: UInt32,
        canonicalName: String
    ) {
        self.synchronizationSource = synchronizationSource
        self.ntpTimestamp = ntpTimestamp
        self.rtpTimestamp = rtpTimestamp
        self.packetCount = packetCount
        self.octetCount = octetCount
        self.canonicalName = canonicalName
    }
}

public enum RTCPSenderReportParser {
    private static let version: UInt8 = 2
    private static let senderReportPacketType: UInt8 = 200
    private static let sourceDescriptionPacketType: UInt8 = 202
    private static let sourceDescriptionEnd: UInt8 = 0
    private static let canonicalNameItemType: UInt8 = 1
    private static let headerSize = 4
    private static let senderReportFixedSize = 28
    private static let reportBlockSize = 24

    public static func parse(_ data: Data) -> RTCPSenderReport? {
        let bytes = [UInt8](data)
        guard
            bytes.count >= headerSize,
            bytes.count <= RTPAudioConstants.maximumPacketSize,
            bytes.count.isMultiple(of: MemoryLayout<UInt32>.size)
        else {
            return nil
        }

        var senderReport: RTCPSenderReport?
        var canonicalName: String?
        var offset = 0
        var packetIndex = 0

        while offset < bytes.count {
            guard bytes.count - offset >= headerSize else {
                return nil
            }

            let firstByte = bytes[offset]
            let packetVersion = firstByte >> 6
            let hasPadding = firstByte & 0x20 != 0
            let reportCount = Int(firstByte & 0x1F)
            let packetType = bytes[offset + 1]
            let lengthWords = Int(readUInt16(bytes, at: offset + 2))
            let blockSize = (lengthWords + 1) * MemoryLayout<UInt32>.size

            guard
                packetVersion == version,
                blockSize >= headerSize,
                blockSize <= bytes.count - offset,
                packetIndex != 0 || packetType == senderReportPacketType
            else {
                return nil
            }

            var contentSize = blockSize
            if hasPadding {
                guard offset + blockSize == bytes.count else {
                    return nil
                }
                let paddingSize = Int(bytes[offset + blockSize - 1])
                guard paddingSize > 0, paddingSize <= blockSize - headerSize else {
                    return nil
                }
                contentSize -= paddingSize
            }

            if packetType == senderReportPacketType {
                let requiredSize = senderReportFixedSize + reportCount * reportBlockSize
                guard senderReport == nil, contentSize == requiredSize else {
                    return nil
                }

                let synchronizationSource = readUInt32(bytes, at: offset + 4)
                guard synchronizationSource != 0 else {
                    return nil
                }
                senderReport = RTCPSenderReport(
                    synchronizationSource: synchronizationSource,
                    ntpTimestamp: UInt64(readUInt32(bytes, at: offset + 8)) << 32
                        | UInt64(readUInt32(bytes, at: offset + 12)),
                    rtpTimestamp: readUInt32(bytes, at: offset + 16),
                    packetCount: readUInt32(bytes, at: offset + 20),
                    octetCount: readUInt32(bytes, at: offset + 24),
                    canonicalName: ""
                )
            } else if packetType == sourceDescriptionPacketType {
                guard
                    let senderReport,
                    let parsedCanonicalName = parseSourceDescriptions(
                        bytes: bytes,
                        blockOffset: offset,
                        contentSize: contentSize,
                        sourceCount: reportCount,
                        senderSource: senderReport.synchronizationSource
                    ),
                    canonicalName == nil
                else {
                    return nil
                }
                canonicalName = parsedCanonicalName
            }

            offset += blockSize
            packetIndex += 1
        }

        guard let senderReport, let canonicalName else {
            return nil
        }
        return RTCPSenderReport(
            synchronizationSource: senderReport.synchronizationSource,
            ntpTimestamp: senderReport.ntpTimestamp,
            rtpTimestamp: senderReport.rtpTimestamp,
            packetCount: senderReport.packetCount,
            octetCount: senderReport.octetCount,
            canonicalName: canonicalName
        )
    }

    private static func parseSourceDescriptions(
        bytes: [UInt8],
        blockOffset: Int,
        contentSize: Int,
        sourceCount: Int,
        senderSource: UInt32
    ) -> String? {
        let blockEnd = blockOffset + contentSize
        var offset = blockOffset + headerSize
        var canonicalName: String?

        for _ in 0..<sourceCount {
            guard offset + MemoryLayout<UInt32>.size <= blockEnd else {
                return nil
            }

            let chunkStart = offset
            let chunkSource = readUInt32(bytes, at: offset)
            offset += MemoryLayout<UInt32>.size
            var foundEnd = false

            while offset < blockEnd {
                let itemType = bytes[offset]
                offset += 1
                if itemType == sourceDescriptionEnd {
                    foundEnd = true
                    break
                }

                guard offset < blockEnd else {
                    return nil
                }
                let itemLength = Int(bytes[offset])
                offset += 1
                guard itemLength <= blockEnd - offset else {
                    return nil
                }

                if itemType == canonicalNameItemType, chunkSource == senderSource {
                    guard itemLength > 0, canonicalName == nil else {
                        return nil
                    }
                    canonicalName = String(
                        decoding: bytes[offset..<(offset + itemLength)], as: UTF8.self)
                }
                offset += itemLength
            }

            guard foundEnd else {
                return nil
            }

            let paddedChunkSize = alignedToWord(offset - chunkStart)
            guard paddedChunkSize <= blockEnd - chunkStart else {
                return nil
            }
            let paddedEnd = chunkStart + paddedChunkSize
            guard bytes[offset..<paddedEnd].allSatisfy({ $0 == 0 }) else {
                return nil
            }
            offset = paddedEnd
        }

        guard bytes[offset..<blockEnd].allSatisfy({ $0 == 0 }) else {
            return nil
        }
        return canonicalName
    }

    private static func alignedToWord(_ size: Int) -> Int {
        (size + MemoryLayout<UInt32>.size - 1) & ~(MemoryLayout<UInt32>.size - 1)
    }
}

public func signedRTPTimestampDifference(_ timestamp: UInt32, reference: UInt32) -> Int32 {
    Int32(bitPattern: timestamp &- reference)
}

private func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
}

private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) << 24
        | UInt32(bytes[offset + 1]) << 16
        | UInt32(bytes[offset + 2]) << 8
        | UInt32(bytes[offset + 3])
}
