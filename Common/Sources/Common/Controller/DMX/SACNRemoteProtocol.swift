import Foundation

public struct SACNRemoteHello: Codable, Sendable {
    public let type: String
    public let viewerName: String
    public let viewerVersion: String
    public let universe: UInt16

    public init(viewerName: String, viewerVersion: String, universe: UInt16) {
        self.type = "hello"
        self.viewerName = viewerName
        self.viewerVersion = viewerVersion
        self.universe = universe
    }
}

public enum SACNRemoteStream {
    public static let maxPacketSize = 1500
    public static let lengthPrefixSize = 2
}
