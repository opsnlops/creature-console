import Foundation

/// A notice from the server that we should pay attention to
public struct Notice: Decodable {

    public var timestamp: Date
    public var message: String
}
