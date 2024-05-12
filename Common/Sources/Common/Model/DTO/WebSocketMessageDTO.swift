import Foundation

/// All incoming messages are going to look like this. The `payload` varies, but we can determine the decoder
/// to use based on the command.
public struct WebSocketMessageDTO: Decodable {
    let command: String
    let payload: PayloadContainer

    // Custom init to pass the command to PayloadContainer
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        payload = try PayloadContainer(from: container, command: command)
    }

    public enum CodingKeys: String, CodingKey {
        case command
        case payload
    }

    // Enum to handle multiple payloads
    public enum PayloadContainer: Decodable {
        case notice(Notice)
        case log(ServerLogItem)
        case serverCounters(SystemCountersDTO)
        case unknown

        // Decode based on the command type
        public init(
            from container: KeyedDecodingContainer<WebSocketMessageDTO.CodingKeys>, command: String
        ) throws {
            switch command {
            case "notice":
                if let notice = try? container.decode(Notice.self, forKey: .payload) {
                    self = .notice(notice)
                } else {
                    self = .unknown
                }

            case "log":
                if let logItem = try? container.decode(ServerLogItem.self, forKey: .payload) {
                    self = .log(logItem)
                } else {
                    self = .unknown
                }

            case "server-counters":
                if let counters = try? container.decode(SystemCountersDTO.self, forKey: .payload) {
                    self = .serverCounters(counters)
                } else {
                    self = .unknown
                }

            default:
                self = .unknown
            }
        }
    }
}
