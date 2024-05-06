
import Combine
import Foundation
import OSLog



extension Notification.Name {
    static let didReceiveCommand = Notification.Name("didReceiveCommand")
}



extension CreatureServerRestful {


    func connectWebsocket() {
        guard let url = URL(string: makeBaseURL(.websocket) + "/websocket") else { return }
        print(url)
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessages()
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    self.logger.error("Websocket received error: \(error)")
                }
            }, receiveValue: { message in
                self.logger.debug("Received message: \(message)")
                NotificationCenter.default.post(name: .didReceiveCommand, object: nil, userInfo: ["message": message])
            })
            .store(in: &cancellables)
    }

    private func receiveMessages() -> AnyPublisher<String, Error> {
        let subject = PassthroughSubject<String, Error>()

        // Declare the closure variable first
        var receiveMessage: (() -> Void)!

        // Define the closure, referring to itself recursively
        receiveMessage = {
            [weak self, weak subject] in
            self?.webSocketTask?.receive { result in
                switch result {
                case .failure(let error):
                    subject?.send(completion: .failure(error))
                case .success(let message):
                    switch message {
                    case .string(let text):
                        subject?.send(text)

                        if let incomingData = text.data(using: .utf8) {
                            self?.decodeIncomingMessage(incomingData)
                        }


                        receiveMessage() // Recursive call to continue receiving messages
                    case .data(let data):
                        print(data)

                        // Handle data if needed, or convert to string and send
                        receiveMessage() // Recursive call to continue receiving messages
                    @unknown default:
                        fatalError("Unknown message type received from WebSocket")
                    }
                }
            }
        }

        // Start receiving messages
        receiveMessage()

        return subject.eraseToAnyPublisher()
    }


    func sendMessage(_ message: String) async -> Result<String, ServerError> {
        let messageToSend = URLSessionWebSocketTask.Message.string(message)

        return await withCheckedContinuation { continuation in
            // Send the message via WebSocket
            webSocketTask?.send(messageToSend) { error in
                if let error = error {
                    self.logger.error("WebSocket sending error: \(error.localizedDescription)")
                    continuation.resume(returning: .failure(.websocketError(error.localizedDescription)))
                } else {
                    self.logger.debug("Message sent: \(message)")
                    continuation.resume(returning: .success(message))
                }
            }
        }
    }

    func disconnectWebsocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }


    private func decodeIncomingMessage(_ message: Data) {
        let logger = Logger() // Replace with your actual logger instance
        logger.debug("Attempting to decode an incoming message from the websocket")

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
                    print("[NOTICE] [\(formatToLocalTime(notice.timestamp))] \(notice.message)")
                } else {
                    print("Decoding as Notice failed")
                }

            case .logging:
                if case .log(let logItem) = incoming.payload {
                    print("[LOG] [\(formatToLocalTime(logItem.timestamp))] [\(logItem.level)] \(logItem.message)")
                } else {
                    print("Decoding as Log failed")
                }

            case .serverCounters:
                if case .serverCounters(let counters) = incoming.payload {
                    print("[COUNTERS] Server is on frame \(counters.totalFrames)")
                } else {
                    print("Decoding as counters")
                }

            default:
                print("Unknown message type: \(incoming.command)")
            }

        } catch {
            print("Error decoding message: \(error.localizedDescription)")
        }
    }

}



