import Foundation
import Logging
import Network

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

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
            NotificationCenter.default.post(
                name: WebSocketClient.didEncounterErrorNotification,
                object: "Invalid URL for WebSocket connection."
            )
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

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private var shouldStayConnected: Bool = false

    private var pathMonitor: NWPathMonitor?
    private var pathMonitorQueue = DispatchQueue(label: "WebSocketPathMonitor")

    #if canImport(UIKit)
        private var foregroundObserver: NSObjectProtocol?
        private var backgroundObserver: NSObjectProtocol?
    #endif
    #if canImport(AppKit)
        private var willSleepObserver: NSObjectProtocol?
        private var didWakeObserver: NSObjectProtocol?
        private var appDidBecomeActiveObserver: NSObjectProtocol?
    #endif

    private let url: URL
    private var messageProcessor: MessageProcessor?

    private let logger = Logger(label: "io.opsnlops.CreatureController.WebSocketClient")

    static let shouldRefreshCachesNotification = Notification.Name("WebSocketShouldRefreshCaches")
    static let didEncounterErrorNotification = Notification.Name("WebSocketDidEncounterError")

    private var hasAlertedForDisconnect: Bool = false

    private var consecutiveErrorCount: Int = 0
    private let errorNotificationSuppressionThreshold: Int = 2
    private var suppressErrorNotifications: Bool = false

    init(url: URL, messageProcessor: MessageProcessor?) {
        self.url = url
        self.messageProcessor = messageProcessor

        logger.info("attempting to make a new WebSocketClient with url \(url)")

        // Create URLSession configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        self.session = URLSession(configuration: config)
    }

    private func handlePathUpdate(_ path: NWPath) async {
        if path.status == .satisfied {
            logger.debug("Network reachable. Considering reconnect if needed.")
            suppressErrorNotifications = false
            if shouldStayConnected, !isConnected {
                await scheduleReconnect(immediate: true)
            }
        } else {
            logger.warning("Network unreachable. Marking connection as down.")
            suppressErrorNotifications = true
            isConnected = false
        }
    }

    #if canImport(UIKit)
        @MainActor
        private func handleWillEnterForeground() async {
            await self.handleAppWillEnterForeground()
        }
    #endif

    private func handleAppWillEnterForeground() async {
        logger.debug("App will enter foreground. Considering reconnect.")
        suppressErrorNotifications = false
        consecutiveErrorCount = 0
        if shouldStayConnected, !isConnected {
            await scheduleReconnect(immediate: true)
        }
    }

    private func handleDidEnterBackground() async {
        logger.debug("App did enter background. Pausing pings.")
        suppressErrorNotifications = true
        await pausePinging()
    }

    private func handleWillSleep() async {
        logger.debug("System will sleep. Marking connection down and pausing.")
        suppressErrorNotifications = true
        isConnected = false
        await pausePinging()
    }

    private func handleWakeOrActivate() async {
        logger.debug("Wake/Activate. Considering reconnect and resuming pings.")
        suppressErrorNotifications = false
        consecutiveErrorCount = 0
        if shouldStayConnected, !isConnected {
            await scheduleReconnect(immediate: true)
        }
        await resumePingingIfNeeded()
        NotificationCenter.default.post(
            name: WebSocketClient.shouldRefreshCachesNotification, object: nil)
    }

    private func performScheduledReconnect(immediate: Bool) async {
        if immediate {
            await attemptReconnect()
            return
        }
        let delay = nextBackoffDelay()
        logger.debug(
            "Scheduling reconnect in \(String(format: "%.2f", delay))s (attempt #\(reconnectAttempt + 1))"
        )
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await attemptReconnect()
    }

    private func setupLifecycleMonitoring() {
        // Monitor network path changes
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                guard let self else { return }
                await self.handlePathUpdate(path)
            }
        }
        monitor.start(queue: pathMonitorQueue)

        #if canImport(UIKit)
            // Observe app lifecycle to reconnect when returning to foreground
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil,
                queue: OperationQueue.main
            ) { [weak self] (_: Notification) in
                Task { [weak self] in
                    guard let self else { return }
                    await self.handleWakeOrActivate()
                }
            }

            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil,
                queue: OperationQueue.main
            ) { [weak self] (_: Notification) in
                Task { [weak self] in
                    guard let self else { return }
                    await self.handleDidEnterBackground()
                }
            }
        #endif
        #if canImport(AppKit)
            // Observe macOS sleep/wake and activation to maintain/reconnect the socket
            let nc = NSWorkspace.shared.notificationCenter

            willSleepObserver = nc.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: OperationQueue.main
            ) { [weak self] (_: Notification) in
                Task { [weak self] in
                    guard let self else { return }
                    await self.handleWillSleep()
                }
            }

            didWakeObserver = nc.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: OperationQueue.main
            ) { [weak self] (_: Notification) in
                Task { [weak self] in
                    guard let self else { return }
                    await self.handleWakeOrActivate()
                }
            }

            appDidBecomeActiveObserver = nc.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil,
                queue: OperationQueue.main
            ) { [weak self] (_: Notification) in
                Task { [weak self] in
                    guard let self else { return }
                    await self.handleWakeOrActivate()
                }
            }
        #endif
    }

    private func teardownLifecycleMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        #if canImport(UIKit)
            if let fg = foregroundObserver { NotificationCenter.default.removeObserver(fg) }
            if let bg = backgroundObserver { NotificationCenter.default.removeObserver(bg) }
            foregroundObserver = nil
            backgroundObserver = nil
        #endif
        #if canImport(AppKit)
            let nc = NSWorkspace.shared.notificationCenter
            if let o = willSleepObserver { nc.removeObserver(o) }
            if let o = didWakeObserver { nc.removeObserver(o) }
            if let o = appDidBecomeActiveObserver { nc.removeObserver(o) }
            willSleepObserver = nil
            didWakeObserver = nil
            appDidBecomeActiveObserver = nil
        #endif
    }

    private func scheduleReconnect(immediate: Bool = false) async {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.performScheduledReconnect(immediate: immediate)
        }
    }

    private func nextBackoffDelay() -> Double {
        // Exponential backoff with jitter: base 1s, cap 30s
        let base: Double = 1
        let maxDelay: Double = 30
        let exp = min(reconnectAttempt, 5)  // cap exponent growth
        let raw = pow(2.0, Double(exp)) * base
        let jitter = Double.random(in: 0...0.5)
        return min(raw + jitter, maxDelay)
    }

    private func attemptReconnect() async {
        guard shouldStayConnected, !isConnected else { return }
        self.logger.info("Attempting websocket reconnect (attempt #\(reconnectAttempt + 1))")
        self.connect()
        // If connect succeeds, startReceiving() will loop. We'll mark success here after a small check.
        // Give it a moment to establish; if still not connected, schedule another try.
        try? await Task.sleep(for: .seconds(1))
        if !isConnected {
            reconnectAttempt += 1
            await scheduleReconnect()
        } else {
            reconnectAttempt = 0
        }
    }

    func connect() {
        shouldStayConnected = true
        reconnectTask?.cancel()
        setupLifecycleMonitoring()

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        task = session.webSocketTask(with: request)
        task?.resume()
        isConnected = true
        hasAlertedForDisconnect = false
        reconnectAttempt = 0
        consecutiveErrorCount = 0
        suppressErrorNotifications = false

        logger.info("websocket is connected")
        startReceiving()
        startPinging()
        NotificationCenter.default.post(
            name: WebSocketClient.shouldRefreshCachesNotification, object: nil)
    }

    func disconnect() {
        shouldStayConnected = false
        reconnectTask?.cancel()

        task?.cancel(with: .goingAway, reason: nil)
        pingTask?.cancel()
        reconnectTask?.cancel()
        task = nil
        pingTask = nil
        isConnected = false

        teardownLifecycleMonitoring()

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
                if await self?.isConnected == true {
                    await self?.startReceiving()
                }
            } catch {
                await self?.handleError(error)
                if await self?.shouldStayConnected == true {
                    await self?.scheduleReconnect()
                }
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

    private func pausePinging() async {
        pingTask?.cancel()
        pingTask = nil
        logger.debug("Ping paused")
    }

    private func resumePingingIfNeeded() async {
        guard isConnected, pingTask == nil else { return }
        logger.debug("Resuming ping task")
        startPinging()
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        consecutiveErrorCount = 0
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

    private func handleError(_ error: Error) async {
        isConnected = false
        pingTask?.cancel()
        reconnectTask?.cancel()
        await pausePinging()

        if let urlError = error as? URLError {
            logger.warning("websocket encountered URLError: \(urlError.localizedDescription)")
        } else {
            logger.warning("websocket encountered an error: \(error.localizedDescription)")
        }

        if suppressErrorNotifications {
            logger.info(
                "Suppressing websocket error while in background/sleep or offline: \(error.localizedDescription)"
            )
        } else {
            consecutiveErrorCount += 1
            if consecutiveErrorCount <= errorNotificationSuppressionThreshold {
                logger.info(
                    "Suppressing transient websocket error (\(consecutiveErrorCount)/\(errorNotificationSuppressionThreshold)): \(error.localizedDescription)"
                )
            } else if !hasAlertedForDisconnect {
                NotificationCenter.default.post(
                    name: WebSocketClient.didEncounterErrorNotification,
                    object:
                        "Lost connection to server. Will attempt to reconnect. Error: \(error.localizedDescription)"
                )
                hasAlertedForDisconnect = true
            }
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
            // Mark as disconnected and attempt a reconnect if desired
            self.isConnected = false
            await self.scheduleReconnect()
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
