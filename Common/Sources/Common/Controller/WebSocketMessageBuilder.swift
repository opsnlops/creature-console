import Foundation

public struct WebSocketMessageBuilder {
    public static func createMessage<T: Codable>(type: ServerMessageType, payload: T) throws
        -> String
    {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Create the complete message object with command and payload
        let message = WebSocketMessageDTO(command: type.rawValue, payload: payload)

        // Encode the entire message object to JSON
        let messageData = try encoder.encode(message)

        // Convert the JSON data to a String to be returned
        return String(data: messageData, encoding: .utf8) ?? "{}"
    }
}
