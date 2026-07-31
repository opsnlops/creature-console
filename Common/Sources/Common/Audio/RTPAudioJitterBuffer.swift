import Foundation

/// A bounded, timestamp-keyed packet buffer for one RTP synchronization source.
///
/// The owner is responsible for serialization. Keeping synchronization outside this type lets
/// the live audio scheduler perform packet insertion and playout on one dispatch queue without
/// putting a lock in the hot path.
public struct RTPAudioJitterBuffer: Sendable {
    public enum InsertResult: Equatable, Sendable {
        case inserted
        case duplicate
        case newSynchronizationSource
        case rejectedLate
    }

    private let capacity: Int
    private var packets: [UInt32: OpusRTPPacket] = [:]
    private(set) public var synchronizationSource: UInt32?
    private(set) public var newestTimestamp: UInt32?
    private(set) public var playoutTimestamp: UInt32?

    public init(capacity: Int = 64) {
        precondition(capacity > 1)
        self.capacity = capacity
    }

    public var packetCount: Int {
        packets.count
    }

    public mutating func insert(_ packet: OpusRTPPacket) -> InsertResult {
        let result: InsertResult
        if synchronizationSource != packet.synchronizationSource {
            packets.removeAll(keepingCapacity: true)
            synchronizationSource = packet.synchronizationSource
            newestTimestamp = nil
            playoutTimestamp = nil
            result = .newSynchronizationSource
        } else {
            result = .inserted
        }

        if let playoutTimestamp,
            signedRTPTimestampDifference(packet.timestamp, reference: playoutTimestamp) < 0
        {
            return .rejectedLate
        }
        guard packets[packet.timestamp] == nil else {
            return .duplicate
        }

        packets[packet.timestamp] = packet
        if newestTimestamp == nil
            || signedRTPTimestampDifference(packet.timestamp, reference: newestTimestamp!) > 0
        {
            newestTimestamp = packet.timestamp
        }
        trimToCapacity()
        return result
    }

    public func packet(at timestamp: UInt32) -> OpusRTPPacket? {
        packets[timestamp]
    }

    public func hasPacket(after timestamp: UInt32) -> Bool {
        packets.keys.contains {
            signedRTPTimestampDifference($0, reference: timestamp) > 0
        }
    }

    public mutating func takePacket(at timestamp: UInt32) -> OpusRTPPacket? {
        playoutTimestamp = timestamp
        return packets.removeValue(forKey: timestamp)
    }

    public mutating func discard(before timestamp: UInt32) {
        packets = packets.filter {
            signedRTPTimestampDifference($0.key, reference: timestamp) >= 0
        }
        playoutTimestamp = timestamp
    }

    public mutating func reset() {
        packets.removeAll(keepingCapacity: true)
        synchronizationSource = nil
        newestTimestamp = nil
        playoutTimestamp = nil
    }

    public func earliestTimestamp() -> UInt32? {
        packets.keys.min {
            signedRTPTimestampDifference($0, reference: $1) < 0
        }
    }

    private mutating func trimToCapacity() {
        while packets.count > capacity, let oldest = earliestTimestamp() {
            packets.removeValue(forKey: oldest)
        }
    }
}
