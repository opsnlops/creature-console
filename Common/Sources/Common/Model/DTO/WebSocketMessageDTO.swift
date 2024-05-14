import Foundation

/// Represents a WebSocket message with a command and a dynamically typed payload.
public struct WebSocketMessageDTO<T: Codable>: Codable {
    public let command: String
    public let payload: T

    public enum CodingKeys: String, CodingKey {
        case command, payload
    }


    public init(command: String, payload: T) {
        self.command = command
        self.payload = payload
    }

    /// Custom initializer from decoder to handle dynamic decoding based on the command.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)

        switch ServerMessageType(rawValue: command) {
        case .notice:
            payload = try container.decode(Notice.self, forKey: .payload) as! T
        case .logging:
            payload = try container.decode(ServerLogItem.self, forKey: .payload) as! T
        case .serverCounters:
            payload = try container.decode(SystemCountersDTO.self, forKey: .payload) as! T
        case .streamFrame:
            payload = try container.decode(StreamFrameData.self, forKey: .payload) as! T
        case .statusLights:
            payload = try container.decode(VirtualStatusLightsDTO.self, forKey: .payload) as! T
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .payload, in: container, debugDescription: "Unknown command")
        }
    }
}
