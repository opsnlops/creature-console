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
        case .boardSensorReport:
            payload = try container.decode(BoardSensorReport.self, forKey: .payload) as! T
        case .cacheInvalidation:
            payload = try container.decode(CacheInvalidation.self, forKey: .payload) as! T
        case .emergencyStop:
            payload = try container.decode(EmergencyStop.self, forKey: .payload) as! T
        case .logging:
            payload = try container.decode(ServerLogItem.self, forKey: .payload) as! T
        case .motorSensorReport:
            payload = try container.decode(MotorSensorReport.self, forKey: .payload) as! T
        case .notice:
            payload = try container.decode(Notice.self, forKey: .payload) as! T
        case .playlistStatus:
            payload = try container.decode(PlaylistStatus.self, forKey: .payload) as! T
        case .serverCounters:
            payload = try container.decode(SystemCountersDTO.self, forKey: .payload) as! T
        case .statusLights:
            payload = try container.decode(VirtualStatusLightsDTO.self, forKey: .payload) as! T
        case .streamFrame:
            payload = try container.decode(StreamFrameData.self, forKey: .payload) as! T
        case .watchdogWarning:
            payload = try container.decode(WatchdogWarning.self, forKey: .payload) as! T
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .payload, in: container, debugDescription: "Unknown command")
        }
    }
}
