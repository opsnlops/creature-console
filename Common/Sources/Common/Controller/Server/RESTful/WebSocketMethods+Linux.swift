#if os(Linux)
    import Foundation
    import Logging
    import NIOCore
    import NIOHTTP1
    import NIOPosix
    import NIOWebSocket
    @preconcurrency import NIOSSL

    actor WebSocketClient {
        private let url: URL
        private var messageProcessor: MessageProcessor?
        private let headers: [String: String]
        static let logger: Logger = {
            var l = Logger(label: "io.opsnlops.CreatureController.WebSocketClient.Linux")
            l.logLevel = .info
            return l
        }()

        private var channel: Channel?
        private var isConnected: Bool = false
        private var isConnecting: Bool = false
        private var shouldStayConnected: Bool = false
        private var reconnectAttempt: Int = 0

        static let shouldRefreshCachesNotification = Notification.Name(
            "WebSocketShouldRefreshCaches")
        static let didEncounterErrorNotification = Notification.Name("WebSocketDidEncounterError")

        init(url: URL, messageProcessor: MessageProcessor?, headers: [String: String] = [:]) {
            self.url = url
            self.messageProcessor = messageProcessor
            self.headers = headers
        }

        func connect() {
            guard !isConnecting else { return }
            isConnecting = true
            shouldStayConnected = true
            Task { [weak self] in
                guard let self else { return }
                await self.startConnection()
            }
        }

        func disconnect() {
            shouldStayConnected = false
            reconnectAttempt = 0
            Task { [weak self] in
                guard let self else { return }
                await self.closeChannel()
                await WebSocketStateManager.shared.setState(.disconnected)
            }
        }

        nonisolated var isWebSocketConnected: Bool {
            get async { await isConnected }
        }

        private func startConnection() async {
            let useTLS = url.scheme?.lowercased() == "wss"
            let host = url.host ?? "localhost"
            let port = url.port ?? (useTLS ? 443 : 80)
            var path = url.path.isEmpty ? "/" : url.path
            if let query = url.query, !query.isEmpty {
                path += "?\(query)"
            }

            await WebSocketStateManager.shared.setState(.connecting)
            Self.logger.info("Initiating NIO websocket connection to \(host):\(port)\(path)")

            let group = MultiThreadedEventLoopGroup.singleton

            let sslContext: NIOSSLContext?
            if useTLS {
                do {
                    let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                    sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                } catch {
                    Self.logger.error("Failed to create TLS context: \(error.localizedDescription)")
                    await handleConnectionFailure()
                    return
                }
            } else {
                sslContext = nil
            }

            let initialHandlerName = "initial-request-handler"

            let websocketUpgrader = NIOWebSocketClientUpgrader(
                requestKey: NIOWebSocketClientUpgrader.randomRequestKey(),
                maxFrameSize: 1 << 14,
                automaticErrorHandling: true
            ) { [weak self] channel, _ in
                guard let self else { return channel.eventLoop.makeSucceededFuture(()) }
                return channel.pipeline.addHandler(WebSocketFrameHandler(owner: self)).flatMap {
                    channel.eventLoop.submit { [weak self] in
                        guard let self else { return }
                        let local = channel.localAddress?.description ?? "<unknown>"
                        let remote = channel.remoteAddress?.description ?? "<unknown>"
                        Self.logger.info(
                            "WebSocket pipeline ready; local \(local) ⇄ remote \(remote)")
                        Task { await self.handleUpgradeSucceeded() }
                    }
                }
            }

            let bootstrap = ClientBootstrap(group: group)
                .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .channelInitializer { [headers = self.headers, initialHandlerName] channel in
                    let upgradeConfig: NIOHTTPClientUpgradeConfiguration = (
                        upgraders: [websocketUpgrader],
                        completionHandler: { context in
                            context.pipeline.removeHandler(name: initialHandlerName).whenFailure {
                                error in
                                context.eventLoop.execute {
                                    Logger(
                                        label:
                                            "io.opsnlops.CreatureController.WebSocketClient.Linux"
                                    )
                                    .debug(
                                        "Failed to remove initial request handler after upgrade: \(error)"
                                    )
                                }
                            }
                        }
                    )

                    var handlers: [EventLoopFuture<Void>] = []
                    if let sslContext {
                        do {
                            let tlsHandler = try NIOSSLClientHandler(
                                context: sslContext,
                                serverHostname: host
                            )
                            handlers.append(channel.pipeline.addHandler(tlsHandler))
                        } catch {
                            return channel.eventLoop.makeFailedFuture(error)
                        }
                    }

                    handlers.append(
                        channel.pipeline.addHTTPClientHandlers(withClientUpgrade: upgradeConfig))

                    let requestHandler = HTTPInitialRequestHandler(
                        host: host, port: port, path: path, headers: headers,
                        logger: WebSocketClient.logger)
                    handlers.append(
                        channel.pipeline.addHandler(requestHandler, name: initialHandlerName))

                    return EventLoopFuture.andAllSucceed(handlers, on: channel.eventLoop)
                }

            let connectFuture: EventLoopFuture<Channel> = {
                if port == 0 {
                    return bootstrap.connect(unixDomainSocketPath: host)
                } else {
                    return bootstrap.connect(host: host, port: port)
                }
            }()

            do {
                let chan = try await connectFuture.get()
                channel = chan
                reconnectAttempt = 0
                isConnecting = false
                Self.logger.info("TCP connection established to \(host):\(port), awaiting upgrade")
            } catch {
                Self.logger.warning("Websocket connect failed: \(error.localizedDescription)")
                await handleConnectionFailure()
            }
        }

        fileprivate func handleClose() async {
            isConnected = false
            isConnecting = false
            channel = nil
            await WebSocketStateManager.shared.setState(.disconnected)
            guard shouldStayConnected else { return }
            await scheduleReconnect()
        }

        private func handleConnectionFailure() async {
            isConnected = false
            isConnecting = false
            await WebSocketStateManager.shared.setState(.disconnected)
            guard shouldStayConnected else { return }
            await scheduleReconnect()
        }

        fileprivate func handleFrame(_ frame: WebSocketFrame) {
            switch frame.opcode {
            case .text:
                var data = frame.unmaskedData
                if let string = data.readString(length: data.readableBytes) {
                    Self.logger.debug("Decoding text frame: \(string)")
                    Task { [weak self] in
                        await self?.handleMessageString(string)
                    }
                }
            case .ping:
                writeFrame(.init(fin: true, opcode: .pong, data: frame.data))
            case .connectionClose:
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.channel?.close()
                    await self.handleClose()
                }
            default:
                break
            }
        }

        private func handleMessageString(_ text: String) async {
            guard let data = text.data(using: .utf8) else { return }
            decodeIncomingMessage(data)
        }

        fileprivate func handleUpgradeSucceeded() async {
            isConnected = true
            reconnectAttempt = 0
            await WebSocketStateManager.shared.setState(.connected)
            Self.logger.info("WebSocket upgrade completed")
        }

        func sendMessage(_ message: String) async -> Result<String, ServerError> {
            guard let channel else {
                return .failure(.websocketError("websocket channel is nil"))
            }
            guard isConnected else {
                return .failure(.websocketError("websocket not connected"))
            }
            var buffer = channel.allocator.buffer(capacity: message.utf8.count)
            buffer.writeString(message)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            do {
                Self.logger.debug("Sending websocket text frame length=\(message.utf8.count)")
                try await channel.writeAndFlush(frame)
                return .success("Message sent successfully")
            } catch {
                Self.logger.warning("Failed to send message: \(error.localizedDescription)")
                await handleClose()
                return .failure(
                    .websocketError("Failed to send message: \(error.localizedDescription)"))
            }
        }

        private func decodeIncomingMessage(_ data: Data) {
            Self.logger.debug("Attempting to decode an incoming message from the websocket")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                let commandDTO = try decoder.decode(BasicCommandDTO.self, from: data)
                Self.logger.debug("Incoming command: \(commandDTO.command)")
                let messageType = ServerMessageType(from: commandDTO.command)

                switch messageType {
                case .notice:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<Notice>.self, from: data)
                    messageProcessor?.processNotice(messageDTO.payload)
                case .logging:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<ServerLogItem>.self, from: data)
                    messageProcessor?.processLog(messageDTO.payload)
                case .serverCounters:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<ServerCountersPayload>.self, from: data)
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
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<CacheInvalidation>.self, from: data)
                    messageProcessor?.processCacheInvalidation(messageDTO.payload)
                case .playlistStatus:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<PlaylistStatus>.self, from: data)
                    messageProcessor?.processPlaylistStatus(messageDTO.payload)
                case .emergencyStop:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<EmergencyStop>.self, from: data)
                    messageProcessor?.processEmergencyStop(messageDTO.payload)
                case .watchdogWarning:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<WatchdogWarning>.self, from: data)
                    messageProcessor?.processWatchdogWarning(messageDTO.payload)
                case .jobProgress:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<JobProgress>.self, from: data)
                    messageProcessor?.processJobProgress(messageDTO.payload)
                case .jobComplete:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<JobCompletion>.self, from: data)
                    messageProcessor?.processJobComplete(messageDTO.payload)
                case .idleStateChanged:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<IdleStateChanged>.self, from: data)
                    messageProcessor?.processIdleStateChanged(messageDTO.payload)
                case .creatureActivity:
                    let messageDTO = try decoder.decode(
                        WebSocketMessageDTO<CreatureActivity>.self, from: data)
                    messageProcessor?.processCreatureActivity(messageDTO.payload)
                default:
                    Self.logger.warning(
                        "Unknown message type: \(commandDTO.command), data: \(data)")
                }

            } catch {
                Self.logger.error(
                    "Error decoding message: \(error.localizedDescription), details: \(error)")
                let payloadString: String
                if let utf8 = String(data: data, encoding: .utf8) {
                    payloadString = utf8
                } else {
                    payloadString = data.base64EncodedString()
                }
                let preview = payloadString.prefix(2048)
                Self.logger.error("Offending payload (utf8 if possible, else base64): \(preview)")
            }
        }

        private func writeFrame(_ frame: WebSocketFrame) {
            channel?.writeAndFlush(frame, promise: nil)
        }

        private func closeChannel() async {
            try? await channel?.close()
            channel = nil
        }

        private func scheduleReconnect() async {
            guard !isConnecting else { return }
            reconnectAttempt += 1
            let delay = min(pow(2.0, Double(reconnectAttempt)), 30)
            Self.logger.info("Scheduling websocket reconnect in \(String(format: "%.1f", delay))s")
            try? await Task.sleep(for: .seconds(Int(delay)))
            guard shouldStayConnected else { return }
            isConnecting = false
            connect()
        }
    }

    private final class HTTPInitialRequestHandler: ChannelInboundHandler, RemovableChannelHandler,
        @unchecked Sendable
    {
        // Use a wide inbound type so post-upgrade websocket frames don't crash this handler.
        typealias InboundIn = Any
        typealias OutboundOut = HTTPClientRequestPart

        private let host: String
        private let port: Int
        private let path: String
        private let headers: [String: String]
        private let logger: Logger
        private var responseBuffer: ByteBuffer?
        private var sawUpgradeFailure: Bool = false
        private var upgradeSucceeded: Bool = false

        init(host: String, port: Int, path: String, headers: [String: String], logger: Logger) {
            self.host = host
            self.port = port
            self.path = path
            self.headers = headers
            var updated = logger
            updated.logLevel = .debug
            self.logger = updated
        }

        func channelActive(context: ChannelHandlerContext) {
            var head = HTTPRequestHead(version: .http1_1, method: .GET, uri: path)
            let hostHeader = port == 80 || port == 443 ? host : "\(host):\(port)"
            head.headers.add(name: "Host", value: hostHeader)
            head.headers.add(name: "Sec-WebSocket-Protocol", value: "websocket")
            head.headers.add(name: "User-Agent", value: "creature-mqtt (Linux NIO)")
            for (key, value) in headers {
                head.headers.add(name: key, value: value)
            }
            logger.info(
                "Sending websocket upgrade request to \(hostHeader)\(path) with headers: \(head.headers)"
            )
            print("[ws-debug] upgrade request headers -> \(head.headers)")

            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if upgradeSucceeded {
                // After a successful upgrade the handler is pending removal; pass through without decoding.
                context.fireChannelRead(data)
                return
            }
            let inbound = self.unwrapInboundIn(data)
            guard let part = inbound as? HTTPClientResponsePart else {
                // We received something other than an HTTP response part; forward it.
                logger.debug("Non-HTTP inbound before upgrade completion: \(inbound)")
                print("[ws-debug] non-HTTP inbound before upgrade completion: \(inbound)")
                context.fireChannelRead(data)
                return
            }
            switch part {
            case .head(let response):
                logger.info(
                    "Received upgrade response status \(response.status.code) headers: \(response.headers)"
                )
                print(
                    "[ws-debug] response head status \(response.status.code) headers \(response.headers)"
                )
                if response.status == HTTPResponseStatus.switchingProtocols {
                    upgradeSucceeded = true
                    logger.debug("Upgrade confirmed; removing initial HTTP handler")
                    print("[ws-debug] upgrade confirmed; removing HTTP handler")
                    _ = context.pipeline.removeHandler(self)
                    return
                } else {
                    logger.warning(
                        "WebSocket upgrade failed with HTTP status \(response.status.code). Closing channel."
                    )
                    sawUpgradeFailure = true
                }
            case .body(var bytes):
                if sawUpgradeFailure {
                    if responseBuffer == nil {
                        responseBuffer =
                            context.channel.allocator.buffer(capacity: bytes.readableBytes)
                    }
                    responseBuffer?.writeBuffer(&bytes)
                }
            case .end:
                if sawUpgradeFailure {
                    if let body = responseBuffer, body.readableBytes > 0 {
                        let preview =
                            body.getString(
                                at: body.readerIndex, length: min(body.readableBytes, 2048))
                            ?? "<non-utf8 response body>"
                        logger.warning("Upgrade failure body preview: \(preview)")
                    }
                    responseBuffer = nil
                    sawUpgradeFailure = false
                    context.close(promise: nil)
                    return
                }
            }

            context.fireChannelRead(data)
        }
    }

    private final class WebSocketFrameHandler: ChannelDuplexHandler, @unchecked Sendable {
        typealias InboundIn = WebSocketFrame
        typealias OutboundIn = Never
        typealias OutboundOut = WebSocketFrame

        private weak var owner: WebSocketClient?

        init(owner: WebSocketClient) {
            self.owner = owner
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let frame = self.unwrapInboundIn(data)
            Task { [weak owner] in
                guard let owner else { return }
                WebSocketClient.logger.debug(
                    "Received websocket frame opcode=\(frame.opcode) length=\(frame.unmaskedData.readableBytes)"
                )
                await owner.handleFrame(frame)
            }
        }

        func channelInactive(context: ChannelHandlerContext) {
            Task { [weak owner] in
                guard let owner else { return }
                WebSocketClient.logger
                    .info("WebSocket channel inactive; closing and scheduling reconnect")
                await owner.handleClose()
            }
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            Task { [weak owner] in
                guard let owner else { return }
                WebSocketClient.logger
                    .warning("Websocket channel error: \(error.localizedDescription)")
                await owner.handleClose()
            }
            context.close(promise: nil)
        }
    }
#endif
