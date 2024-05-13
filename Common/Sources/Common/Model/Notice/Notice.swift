import Foundation

/// A notice from the server that we should pay attention to
public struct Notice: Codable {

    public var timestamp: Date
    public var message: String

    // Default init I don't want to use the memberwise one
    public init() {
        self.timestamp = Date()
        self.message = ""
    }
}
