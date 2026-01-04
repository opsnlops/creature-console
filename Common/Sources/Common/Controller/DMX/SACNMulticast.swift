import Foundation

public enum SACNMulticast {
    public static func address(for universe: UInt16) -> String {
        let high = (universe >> 8) & 0xFF
        let low = universe & 0xFF
        return "239.255.\(high).\(low)"
    }
}
