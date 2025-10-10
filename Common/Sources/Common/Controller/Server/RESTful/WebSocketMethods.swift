import Foundation
import Logging
import Network

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

// WebSocket connection states
public enum WebSocketConnectionState: CustomStringConvertible, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case closing

    public var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .closing:
            return "Closing"
        }
    }
}

struct BasicCommandDTO: Codable {
    let command: String
}


extension CreatureServerClient {


    /**
     Connect to the websocket, using the following processor
     */
    public func connectWebsocket(processor: MessageProcessor) async {
        self.processor = processor

        // Notify state change to connecting
        await WebSocketStateManager.shared.setState(.connecting)

        guard let url = URL(string: makeBaseURL(.websocket) + "/websocket") else {
            logger.error("Invalid URL for WebSocket connection.")
            NotificationCenter.default.post(
                name: WebSocketClient.didEncounterErrorNotification,
                object: "Invalid URL for WebSocket connection."
            )
            await WebSocketStateManager.shared.setState(.disconnected)
            return
        }

        // Build headers if API key is configured
        var headers: [String: String] = [:]
        if let key = apiKey {
            headers["x-acw-api-key"] = key
        }

        // Set Host header when using proxy
        if serverProxyHost != nil, apiKey != nil {
            headers["Host"] = "\(serverHostname):\(serverPort)"
        }

        // Create the websocket client
        webSocketClient = WebSocketClient(url: url, messageProcessor: processor, headers: headers)
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
    private var lastPongReceivedAt: Date?
    private let pingInterval: TimeInterval = 15  // Send ping every 15 seconds
    private let pingTimeoutInterval: TimeInterval = 30  // Consider dead if no pong in 30 seconds

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private var shouldStayConnected: Bool = false
    private var isNetworkPathSatisfied: Bool = false
    private var isConnecting: Bool = false  // Prevent concurrent connection attempts

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
    private let headers: [String: String]

    private let logger = Logger(label: "io.opsnlops.CreatureController.WebSocketClient")

    static let shouldRefreshCachesNotification = Notification.Name("WebSocketShouldRefreshCaches")
    static let didEncounterErrorNotification = Notification.Name("WebSocketDidEncounterError")

    private var hasAlertedForDisconnect: Bool = false

    private var consecutiveErrorCount: Int = 0
    private let errorNotificationSuppressionThreshold: Int = 2
    private var suppressErrorNotifications: Bool = false

    init(url: URL, messageProcessor: MessageProcessor?, headers: [String: String] = [:]) {
        self.url = url
        self.messageProcessor = messageProcessor
        self.headers = headers

        logger.info("attempting to make a new WebSocketClient with url \(url)")

        // Create URLSession configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        self.session = URLSession(configuration: config)
    }

    private func isNetworkAvailable() -> Bool {
        return isNetworkPathSatisfied
    }

    private func handlePathUpdate(_ path: NWPath) async {
        if path.status == .satisfied {
            logger.info(
                "Network path now satisfied. Available interfaces: \(path.availableInterfaces.map { $0.type })"
            )
            isNetworkPathSatisfied = true
            suppressErrorNotifications = false
            consecutiveErrorCount = 0

            // Only attempt reconnect if we should stay connected and we're actually disconnected
            if shouldStayConnected, !isConnected {
                logger.info("Network recovered, initiating immediate reconnect")
                await scheduleReconnect(immediate: true)
            }
        } else {
            // Network is unavailable (could be airplane mode, no WiFi, etc.)
            let reason: String
            if path.availableInterfaces.isEmpty {
                reason = "No network interfaces available (likely airplane mode or all radios off)"
            } else {
                reason = "Network path unsatisfied (status: \(path.status))"
            }

            logger.warning("Network became unreachable: \(reason)")
            isNetworkPathSatisfied = false
            suppressErrorNotifications = true

            // Cancel ALL reconnect attempts immediately
            reconnectTask?.cancel()
            reconnectTask = nil

            // Properly clean up the connection when network becomes unavailable
            if isConnected || isConnecting || task != nil {
                logger.info("Cleaning up WebSocket connection due to network loss")
                isConnected = false
                isConnecting = false

                // Cancel ongoing tasks to avoid wasted resources
                pingTask?.cancel()
                pingTask = nil

                // Close the WebSocket task gracefully
                task?.cancel(with: .goingAway, reason: "Network unavailable".data(using: .utf8))
                task = nil
            }

            // Set appropriate state - but DON'T trigger any reconnects
            if shouldStayConnected {
                await WebSocketStateManager.shared.setState(.reconnecting)
            } else {
                await WebSocketStateManager.shared.setState(.disconnected)
            }
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

        // Check if network is available before attempting reconnect
        if shouldStayConnected, !isConnected {
            if isNetworkAvailable() {
                logger.info("Network is available, initiating reconnect after foreground")
                await scheduleReconnect(immediate: true)
            } else {
                logger.info(
                    "Network unavailable after foreground, waiting for path monitor to signal network restoration"
                )
            }
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

        // Check if network is available before attempting reconnect
        if shouldStayConnected, !isConnected {
            if isNetworkAvailable() {
                logger.info("Network is available, initiating reconnect after wake/activate")
                await scheduleReconnect(immediate: true)
            } else {
                logger.info(
                    "Network unavailable after wake/activate, waiting for path monitor to signal network restoration"
                )
            }
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
        // Set initial network state
        self.isNetworkPathSatisfied = monitor.currentPath.status == .satisfied
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
        // Prevent concurrent reconnection attempts
        guard shouldStayConnected, !isConnected, !isConnecting else {
            if isConnecting {
                logger.debug("Already connecting, skipping reconnect attempt")
            }
            return
        }

        // CRITICAL: Do not attempt reconnect if network is unavailable
        guard isNetworkAvailable() else {
            logger.info(
                "Skipping reconnect attempt #\(reconnectAttempt + 1) - network unavailable. Waiting for network restoration."
            )
            return
        }

        reconnectAttempt += 1
        self.logger.info("Attempting websocket reconnect (attempt #\(reconnectAttempt))")
        await WebSocketStateManager.shared.setState(.reconnecting)
        self.connect()
        // If connect succeeds, startReceiving() will loop. We'll mark success here after a small check.
        // Give it a moment to establish; if still not connected, schedule another try.
        try? await Task.sleep(for: .seconds(1))
        if !isConnected, !isConnecting {
            // Only schedule another reconnect if network is still available
            if isNetworkAvailable() {
                await scheduleReconnect()
            } else {
                logger.info("Network became unavailable, stopping reconnect attempts")
            }
        } else if isConnected {
            reconnectAttempt = 0
        }
    }

    func connect() {
        // Prevent concurrent connection attempts
        guard !isConnecting else {
            logger.debug("Connection already in progress, ignoring duplicate connect() call")
            return
        }

        shouldStayConnected = true
        isConnecting = true
        reconnectTask?.cancel()
        setupLifecycleMonitoring()

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        // Apply headers if any are configured
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        task = session.webSocketTask(with: request)
        task?.resume()
        // DO NOT set isConnected = true here - wait for first message to confirm connection
        hasAlertedForDisconnect = false
        // Don't reset reconnectAttempt here - it's managed by attemptReconnect
        consecutiveErrorCount = 0
        suppressErrorNotifications = false
        lastPongReceivedAt = Date()  // Reset pong timer on connect

        logger.info("websocket connection initiated, waiting for first message")
        Task {
            await WebSocketStateManager.shared.setState(.connecting)
        }
        startReceiving()
        startPinging()
    }

    func disconnect() {
        shouldStayConnected = false
        reconnectTask?.cancel()

        Task {
            await WebSocketStateManager.shared.setState(.closing)
        }

        task?.cancel(with: .goingAway, reason: nil)
        pingTask?.cancel()
        reconnectTask?.cancel()
        task = nil
        pingTask = nil
        isConnected = false
        isConnecting = false

        teardownLifecycleMonitoring()

        logger.info("websocket is disconnected")
        Task {
            await WebSocketStateManager.shared.setState(.disconnected)
        }
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
                // Only schedule reconnect if network is available
                if await self?.shouldStayConnected == true, await self?.isNetworkAvailable() == true
                {
                    await self?.scheduleReconnect()
                }
            }
        }
    }

    private func startPinging() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                // Send ping if connected
                if await self.isConnected {
                    await self.task?.sendPing { [weak self] error in
                        Task {
                            guard let self = self else { return }
                            if let error = error {
                                self.logger.warning("Ping failed: \(error.localizedDescription)")
                                await self.handlePingFailure(error)
                            } else {
                                self.logger.debug("Ping sent successfully")
                                await self.recordPongReceived()
                            }
                        }
                    }
                } else {
                    break
                }

                // Sleep in smaller intervals to check timeout more frequently
                for _ in 0..<3 {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { break }

                    // Check for ping timeout every 5 seconds
                    let lastPong = await self.lastPongReceivedAt
                    if let lastPong = lastPong {
                        let timeSinceLastPong = Date().timeIntervalSince(lastPong)
                        if timeSinceLastPong > self.pingTimeoutInterval {
                            self.logger.warning(
                                "Ping timeout: no pong received in \(String(format: "%.1f", timeSinceLastPong))s"
                            )
                            await self.handlePingTimeout()
                            return
                        }
                    }
                }
            }
        }
    }

    private func recordPongReceived() {
        lastPongReceivedAt = Date()
    }

    private func handlePingTimeout() async {
        logger.warning("Ping timeout detected, treating as disconnection")
        isConnected = false
        pingTask?.cancel()
        pingTask = nil
        await WebSocketStateManager.shared.setState(.disconnected)

        // Only schedule reconnect if network is available
        if shouldStayConnected, isNetworkAvailable() {
            await scheduleReconnect()
        }
    }

    private func handlePingFailure(_ error: Error) async {
        logger.warning("Ping failure detected, treating as disconnection")
        isConnected = false
        pingTask?.cancel()
        pingTask = nil
        await WebSocketStateManager.shared.setState(.disconnected)

        // Only schedule reconnect if network is available
        if shouldStayConnected, isNetworkAvailable() {
            await scheduleReconnect()
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
        // Mark as connected when we receive our first message
        if !isConnected {
            isConnected = true
            isConnecting = false  // Connection successful
            reconnectAttempt = 0  // Reset on successful connection
            logger.info("WebSocket connection established (first message received)")
            Task {
                await WebSocketStateManager.shared.setState(.connected)
                // Notify caches to refresh now that we're truly connected
                NotificationCenter.default.post(
                    name: WebSocketClient.shouldRefreshCachesNotification, object: nil)
            }
        }

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
        isConnecting = false  // Connection failed
        pingTask?.cancel()
        reconnectTask?.cancel()
        await pausePinging()

        await WebSocketStateManager.shared.setState(.disconnected)

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
