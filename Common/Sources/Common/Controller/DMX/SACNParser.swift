import Foundation

public struct SACNFrame: Sendable {
    public let universe: UInt16
    public let sequence: UInt8
    public let priority: UInt8
    public let startCode: UInt8
    public let slots: [UInt8]

    public init(
        universe: UInt16, sequence: UInt8, priority: UInt8, startCode: UInt8, slots: [UInt8]
    ) {
        self.universe = universe
        self.sequence = sequence
        self.priority = priority
        self.startCode = startCode
        self.slots = slots
    }
}

public enum SACNParser {
    private static let minimumPacketSize = 126
    private static let universeOffset = 113
    private static let priorityOffset = 108
    private static let sequenceOffset = 111
    private static let propertyValueCountOffset = 123
    private static let propertyValuesOffset = 125
    private static let acnPacketIdentifier: [UInt8] = [
        0x41, 0x53, 0x43, 0x2d, 0x45, 0x31, 0x2e, 0x31, 0x37, 0x00, 0x00, 0x00,
    ]

    public static func parse(data: Data) -> SACNFrame? {
        guard data.count >= minimumPacketSize else {
            return nil
        }

        guard matchesACNPacketIdentifier(data) else {
            return nil
        }

        let universe = readUInt16BE(data, offset: universeOffset)
        let priority = data[safe: priorityOffset] ?? 0
        let sequence = data[safe: sequenceOffset] ?? 0
        let propertyValueCount = Int(readUInt16BE(data, offset: propertyValueCountOffset))

        guard propertyValueCount > 0 else {
            return nil
        }

        let valuesStart = propertyValuesOffset
        let valuesEnd = min(valuesStart + propertyValueCount, data.count)
        guard valuesEnd > valuesStart else {
            return nil
        }

        let propertyValues = data[valuesStart..<valuesEnd]
        guard let startCode = propertyValues.first else {
            return nil
        }

        var slots = Array(repeating: UInt8(0), count: 512)
        let slotValues = propertyValues.dropFirst()
        for (index, value) in slotValues.prefix(512).enumerated() {
            slots[index] = value
        }

        return SACNFrame(
            universe: universe,
            sequence: sequence,
            priority: priority,
            startCode: startCode,
            slots: slots
        )
    }

    private static func matchesACNPacketIdentifier(_ data: Data) -> Bool {
        let identifierStart = 4
        let identifierEnd = identifierStart + acnPacketIdentifier.count
        guard data.count >= identifierEnd else {
            return false
        }

        return data[identifierStart..<identifierEnd].elementsEqual(acnPacketIdentifier)
    }

    private static func readUInt16BE(_ data: Data, offset: Int) -> UInt16 {
        let high = UInt16(data[safe: offset] ?? 0)
        let low = UInt16(data[safe: offset + 1] ?? 0)
        return (high << 8) | low
    }
}

extension Data {
    fileprivate subscript(safe index: Int) -> UInt8? {
        guard index >= 0, index < count else {
            return nil
        }
        return self[index]
    }
}
