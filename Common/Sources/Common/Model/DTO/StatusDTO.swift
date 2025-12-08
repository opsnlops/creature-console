import Foundation

/// The generic Status DTO that we use on the server
public struct StatusDTO: Codable {

    // Status like OK, ERROR
    public var status: String

    // HTTP Status Code
    public var code: UInt16

    // Message
    public var message: String

    // Optional session UUID for scheduled playback
    public var sessionId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case code
        case message
        case sessionId = "session_id"
    }

    public init(status: String, code: UInt16, message: String, sessionId: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.sessionId = sessionId
    }
}
