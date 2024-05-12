import Foundation

/// The generic Status DTO that we use on the server
public struct StatusDTO: Decodable {

    // Status like OK, ERROR
    public var status: String

    // HTTP Status Code
    public var code: UInt16

    // Message
    public var message: String

}
