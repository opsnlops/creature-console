import Foundation
import Logging
import Starscream

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

        // Create the websocket client
        webSocketClient = WebSocketClient(url: url, messageProcessor: processor)
        webSocketClient?.connect()
    }


    public func disconnectWebsocket() async -> Result<String, ServerError> {

        guard let ws = webSocketClient else {
            return .failure(
                .websocketError("Unable to disconnect because the websocket client doesn't exist"))
        }

        guard isWebSocketConnected else {
            return .failure(
                .websocketError(
                    "Unable to disconnect the websocket because we're not already connected"))
        }

        ws.disconnect()
        logger.info("disconnected from the websocket")
        return .success("Disconnected from the websocket")

    }


    public func sendMessage(_ message: String) async -> Result<String, ServerError> {

        guard !message.isEmpty else {
            return .failure(.communicationError("unable to send an empty string to the server"))
        }

        guard let ws = webSocketClient else {
            return .failure(
                .websocketError("Unable to send message because the websocket client doesn't exist")
            )
        }

        let result = await ws.sendMessage(message)
        switch result {
        case (.success(let successMessage)):
            logger.debug("message sent successfully: \(message)")
            return .success(successMessage)
        case (.failure(let error)):
            logger.warning("unable to send message: \(error.localizedDescription)")
            return .failure(error)
        }
    }

}


class WebSocketClient {
    var socket: WebSocket?
    public var isConnected: Bool = false
    private var pingTimer: Timer?

    private var url: URL
    private var messageProcessor: MessageProcessor?

    private var logger = Logger(label: "io.opsnlops.CreatureController.WebSocketClient")

    init(url: URL, messageProcessor: MessageProcessor?) {
        self.url = url
        self.messageProcessor = messageProcessor

        logger.info("attempting to make a new WebSocketClient with url \(url)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 5  // Sets the timeout for the connection
        socket = WebSocket(request: request)


    }

    func connect() {
        socket?.delegate = self
        socket?.connect()
        startPinging()
    }

    func disconnect() {
        socket?.disconnect()
        isConnected = false
        socket = nil
    }

    private func startPinging() {
        // Schedule a timer to send a ping every 10 seconds
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopPinging() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        guard isConnected else { return }
        socket?.write(
            ping: Data(),
            completion: {
                self.logger.debug("Ping sent")
            })
    }

    func sendMessage(_ message: String) async -> Result<String, ServerError> {

        guard let ws = socket else {
            return .failure(.websocketError("websocket socket is nil"))
        }

        guard isConnected else {
            return .failure(.websocketError("Unable to send message because we're not connected"))
        }

        logger.debug("sending message on websocket: \(message)")
        ws.write(string: message)
        return .success("Message written to websocket")
    }
}


extension WebSocketClient: WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected(let headers):
            isConnected = true
            startPinging()
            print("websocket is connected: \(headers)")
        case .disconnected(let reason, let code):
            isConnected = false
            stopPinging()
            print("websocket is disconnected: \(reason) with code: \(code)")
        case .text(let string):
            logger.trace("string received from the websocket: \(string)")

            // Make sure we can decode this
            if let data = string.data(using: .utf8) {
                decodeIncomingMessage(data)
            } else {
                logger.warning("unable to decode incoming string as UTF-8: \(string)")
            }


        case .binary(let data):
            logger.debug("Received data: \(data.count)")
        case .ping(_):
            logger.debug("ping received")
        case .pong(_):
            logger.debug("pong received")
        case .viabilityChanged(_):
            break
        case .reconnectSuggested(_):
            logger.info("reconnect suggested to the WebSocket")
        case .cancelled:
            isConnected = false
        case .error(let error):
            isConnected = false
            _ = handleError(error)
        case .peerClosed:
            break
        }
    }

    func handleError(_ error: Error?) -> ServerError {
        if let e = error as? WSError {
            logger.warning("websocket encountered an error: \(e.message)")
            return .serverError("websocket encountered an error: \(e.message)")
        } else if let e = error {
            logger.warning("websocket encountered an error: \(e.localizedDescription)")
            return .serverError("websocket encountered an error: \(e.localizedDescription)")
        } else {
            logger.warning("websocket encountered an error")
            return .serverError("websocket encountered an error")
        }
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
                    messageProcessor?.processNotice(notice)
                } else {
                    self.logger.warning("Decoding a notice failed")
                }


            case .logging:
                if case .log(let logItem) = incoming.payload {
                    messageProcessor?.processLog(logItem)
                } else {
                    self.logger.warning("Decoding as Log failed")
                }


            case .serverCounters:
                if case .serverCounters(let counters) = incoming.payload {
                    messageProcessor?.processSystemCounters(counters)
                } else {
                    self.logger.warning("Decoding a serverCounters message failed")
                }

            case .statusLights:
                if case .statusLights(let statusLights) = incoming.payload {
                    messageProcessor?.processStatusLights(statusLights)
                } else {
                    self.logger.warning("Decoding a statusLights message failed")
                }


            default:
                self.logger.warning("Unknown message type: \(incoming.command)")
            }

        } catch {
            self.logger.error("Error decoding message: \(error.localizedDescription)")
        }
    }
}
