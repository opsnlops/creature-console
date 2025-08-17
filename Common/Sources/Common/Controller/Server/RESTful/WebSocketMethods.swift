import Foundation
import Logging

struct BasicCommandDTO: Codable {
    let command: String
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
        await webSocketClient?.connect()
    }


    public func disconnectWebsocket() async -> Result<String, ServerError> {

        guard let ws = webSocketClient else {
            return .failure(
                .websocketError("Unable to disconnect because the websocket client doesn't exist"))
        }

        guard await ws.isWebSocketConnected else {
            return .failure(
                .websocketError(
                    "Unable to disconnect the websocket because we're not already connected"))
        }

        await ws.disconnect()
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


actor WebSocketClient {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private var isConnected: Bool = false
    private var pingTask: Task<Void, Never>?

    private let url: URL
    private var messageProcessor: MessageProcessor?

    private let logger = Logger(label: "io.opsnlops.CreatureController.WebSocketClient")

    init(url: URL, messageProcessor: MessageProcessor?) {
        self.url = url
        self.messageProcessor = messageProcessor

        logger.info("attempting to make a new WebSocketClient with url \(url)")

        // Create URLSession configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        self.session = URLSession(configuration: config)
    }

    func connect() {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        task = session.webSocketTask(with: request)
        task?.resume()
        isConnected = true

        logger.info("websocket is connected")
        startReceiving()
        startPinging()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        pingTask?.cancel()
        task = nil
        pingTask = nil
        isConnected = false
        logger.info("websocket is disconnected")
    }

    nonisolated var isWebSocketConnected: Bool {
        get async {
            await isConnected
        }
    }

    private func startReceiving() {
        guard let task = task else { return }

        Task { [weak self] in
            do {
                let message = try await task.receive()
                await self?.handleMessage(message)

                // Continue receiving if still connected
                if await self?.isConnected == true {
                    await self?.startReceiving()
                }
            } catch {
                await self?.handleError(error)
            }
        }
    }

    private func startPinging() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))

                guard !Task.isCancelled else { break }

                if await self?.isConnected == true {
                    await self?.task?.sendPing { [weak self] error in
                        Task {
                            if let error = error {
                                self?.logger.warning("Ping failed: \(error.localizedDescription)")
                            } else {
                                self?.logger.debug("Ping sent")
                            }
                        }
                    }
                } else {
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            logger.trace("string received from the websocket: \(text)")
            if let data = text.data(using: .utf8) {
                decodeIncomingMessage(data)
            } else {
                logger.warning("unable to decode incoming string as UTF-8: \(text)")
            }
        case .data(let data):
            logger.debug("Received binary data: \(data.count) bytes")
        @unknown default:
            logger.warning("Received unknown message type")
        }
    }

    private func handleError(_ error: Error) {
        isConnected = false
        pingTask?.cancel()

        if let urlError = error as? URLError {
            logger.warning("websocket encountered URLError: \(urlError.localizedDescription)")
        } else {
            logger.warning("websocket encountered an error: \(error.localizedDescription)")
        }
    }

    func sendMessage(_ message: String) async -> Result<String, ServerError> {
        guard let task = task else {
            return .failure(.websocketError("websocket task is nil"))
        }

        guard isConnected else {
            return .failure(.websocketError("Unable to send message because we're not connected"))
        }

        do {
            logger.debug("sending message on websocket: \(message)")
            try await task.send(.string(message))
            return .success("Message sent successfully")
        } catch {
            logger.warning("Failed to send message: \(error.localizedDescription)")
            return .failure(
                .websocketError("Failed to send message: \(error.localizedDescription)"))
        }
    }

    private func decodeIncomingMessage(_ data: Data) {
        logger.debug("Attempting to decode an incoming message from the websocket")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            // Decode just to get the command first
            let commandDTO = try decoder.decode(BasicCommandDTO.self, from: data)
            logger.debug("Incoming command: \(commandDTO.command)")
            let messageType = ServerMessageType(from: commandDTO.command)

            // Now decode the full message based on the command
            switch messageType {
            case .notice:
                let messageDTO = try decoder.decode(WebSocketMessageDTO<Notice>.self, from: data)
                messageProcessor?.processNotice(messageDTO.payload)
            case .logging:
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<ServerLogItem>.self, from: data)
                messageProcessor?.processLog(messageDTO.payload)
            case .serverCounters:
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<SystemCountersDTO>.self, from: data)
                messageProcessor?.processSystemCounters(messageDTO.payload)
            case .statusLights:
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<VirtualStatusLightsDTO>.self, from: data)
                messageProcessor?.processStatusLights(messageDTO.payload)
            case .motorSensorReport:
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<MotorSensorReport>.self, from: data)
                messageProcessor?.processMotorSensorReport(messageDTO.payload)
            case .boardSensorReport:
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<BoardSensorReport>.self, from: data)
                messageProcessor?.processBoardSensorReport(messageDTO.payload)
            case .cacheInvalidation:
                logger.debug("cache-invalidation")
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<CacheInvalidation>.self, from: data)
                messageProcessor?.processCacheInvalidation(messageDTO.payload)
            case .playlistStatus:
                logger.debug("playlist")
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<PlaylistStatus>.self, from: data)
                messageProcessor?.processPlaylistStatus(messageDTO.payload)
            case .emergencyStop:
                logger.debug("emergency-stop")
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<EmergencyStop>.self, from: data)
                messageProcessor?.processEmergencyStop(messageDTO.payload)
            case .watchdogWarning:
                logger.debug("watchdog-warning")
                let messageDTO = try decoder.decode(
                    WebSocketMessageDTO<WatchdogWarning>.self, from: data)
                messageProcessor?.processWatchdogWarning(messageDTO.payload)
            default:
                logger.warning("Unknown message type: \(commandDTO.command), data: \(data)")
            }

        } catch {
            logger.error(
                "Error decoding message: \(error.localizedDescription), details: \(error)")
        }
    }
}
