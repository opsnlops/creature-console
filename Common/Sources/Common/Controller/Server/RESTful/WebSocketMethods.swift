

import Foundation
import Logging



extension Notification.Name {
    static let didReceiveCommand = Notification.Name("didReceiveCommand")
}



extension CreatureServerClient {

    

    /**
     Connect to the websocket, using the following processor
     */
    public func connectWebsocket(processor: MessageProcessor) async {
        self.processor = processor

        guard let url = URL(string: makeBaseURL(.websocket) + "/websocket") else {
            logger.error("Invalid URL for WebSocket connection.")
            return
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)

        // Start the WebSocket connection
        webSocketTask?.resume()

        // Receive messages in an asynchronous way
        Task {
            do {
                try await receiveMessages()
            } catch {
                self.logger.error("Websocket received error: \(error)")
                print("Websocket received error: \(error)")
            }
        }

        // Start the pinging
        Task {
           // do {
                 await startPinging()
           // }
        }
    }



    private func receiveMessages() async throws {
        while let message = try await receiveMessage() {
            NotificationCenter.default.post(name: .didReceiveCommand, object: nil, userInfo: ["message": message])
            if let incomingData = message.data(using: .utf8) {
                decodeIncomingMessage(incomingData)
            }
        }
    }

    private func receiveMessage() async throws -> String? {
        do {
            let result = try await webSocketTask?.receive()
            switch result {
                case .string(let text):
                    return text
                case .data(let data):
                    print("Received binary data: \(data)")
                    // Optionally handle binary data
                    return nil
                default:
                    fatalError("Unknown message type received from WebSocket")
            }
        } catch {
            print("WebSocket receive error: \(error)")
            throw error
        }
    }

    func startPinging() async {
        stopPinging()

        // Using an async loop to handle pinging at regular intervals
        pingTimer = true  // Assume pingTimer is now a boolean or similar simple state control

        while pingTimer {
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)  // Sleep for 10 seconds
                try await sendPing()
                self.logger.debug("Ping sent successfully")
            } catch {
                self.logger.error("Ping failed with error: \(error)")
                stopPinging()  // Call stopPinging to handle stopping the timer and cleanup
                return
            }
        }

    }

    private func stopPinging() {
        // Change pingTimer state to false, indicating the ping should no longer continue
        pingTimer = false
    }



    private func sendPing() async throws {
        guard let webSocketTask = webSocketTask else {
            throw ServerError.serverError("Websocket not initialized")
        }
        do {
             webSocketTask.sendPing { error in
                if let error = error {
                    self.logger.error("Ping failed with error: \(error.localizedDescription)")
                    // Here, handle the error without throwing, such as setting an internal state or logging.
                } else {
                    self.logger.debug("Ping received successfully")
                }
            }
        }
    }




    public func sendMessage(_ message: String) async -> Result<String, ServerError> {
        let messageToSend = URLSessionWebSocketTask.Message.string(message)
        do {
            try await webSocketTask?.send(messageToSend)
            self.logger.debug("Message sent: \(message)")
            return .success(message)
        } catch {
            self.logger.error("WebSocket sending error: \(error.localizedDescription)")
            return .failure(.websocketError(error.localizedDescription))
        }
    }


    public func disconnectWebsocket() async {
        // Gracefully close the WebSocket connection
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        // Stop the ping timer
        stopPinging()

        // Clear the message processor
        self.processor = nil

        // Optionally, log that the websocket has disconnected
        self.logger.debug("WebSocket disconnected successfully.")
    }

    

    private func decodeIncomingMessage(_ message: Data) {
        self.logger.debug("Attempting to decode an incoming message from the websocket")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601  // Set to ISO 8601 strategy

        do {
            // Decode the main WebSocket message DTO
            let incoming = try decoder.decode(WebSocketMessageDTO.self, from: message)

            logger.debug("Incoming message is a command of: \(incoming.command)")
            let messageType = ServerMessageType(from: incoming.command)

            // Call specific handlers based on the message type
            switch messageType {


            case .notice:
                if case .notice(let notice) = incoming.payload {
                    processor?.processNotice(notice)
                } else {
                    self.logger.warning("Decoding a notice failed")
                }


            case .logging:
                if case .log(let logItem) = incoming.payload {
                    processor?.processLog(logItem)
                } else {
                    self.logger.warning("Decoding as Log failed")
                }


            case .serverCounters:
                if case .serverCounters(let counters) = incoming.payload {
                    processor?.processSystemCounters(counters)
                } else {
                    self.logger.warning("Decoding a serverCounters message failed")
                }



            default:
                self.logger.warning("Unknown message type: \(incoming.command)")
            }

        } catch {
            self.logger.error("Error decoding message: \(error.localizedDescription)")
        }
    }

}



