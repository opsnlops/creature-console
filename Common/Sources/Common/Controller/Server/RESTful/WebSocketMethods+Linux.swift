#if os(Linux)
    import Foundation
    import Logging
    import NIOCore
    import NIOHTTP1
    import NIOPosix
    import NIOWebSocket
    import NIOSSL

    actor WebSocketClient {
        private let url: URL
        private var messageProcessor: MessageProcessor?
        private let headers: [String: String]
        let logger = Logger(label: "io.opsnlops.CreatureController.WebSocketClient.Linux")

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
                try? await self.channel?.close()
                self.channel = nil
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
            logger.info("Initiating NIO websocket connection to \(host):\(port)\(path)")

            let group = MultiThreadedEventLoopGroup.singleton

            let sslContext: NIOSSLContext?
            if useTLS {
                do {
                    sslContext = try NIOSSLContext(configuration: .forClient())
                } catch {
                    logger.error("Failed to create TLS context: \(error.localizedDescription)")
                    await handleConnectionFailure()
                    return
                }
            } else {
                sslContext = nil
            }

            let websocketUpgrader = NIOWebSocketClientUpgrader(
                requestKey: NIOWebSocketClientUpgrader.randomRequestKey(),
                maxFrameSize: 1 << 14,
                automaticErrorHandling: true
            ) { [weak self] channel, _ in
                guard let self else { return channel.eventLoop.makeSucceededFuture(()) }
                return channel.pipeline.addHandler(WebSocketFrameHandler(owner: self))
            }

            let upgradeConfig: NIOHTTPClientUpgradeConfiguration = (
                upgraders: [websocketUpgrader],
                completionHandler: { _ in }
            )

            let bootstrap = ClientBootstrap(group: group)
                .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .channelInitializer { channel in
                    var handlers: [EventLoopFuture<Void>] = []
                    if let sslContext {
                        let tlsHandler = NIOSSLClientHandler(
                            context: sslContext,
                            serverHostname: host
                        )
                        handlers.append(channel.pipeline.addHandler(tlsHandler))
                    }

                    handlers.append(
                        channel.pipeline.addHTTPClientHandlers(withClientUpgrade: upgradeConfig))

                    let requestHandler = HTTPInitialRequestHandler(
                        host: host, port: port, path: path, headers: self.headers)
                    handlers.append(channel.pipeline.addHandler(requestHandler))

                    return channel.eventLoop.flatten(handlers)
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
                isConnected = true
                isConnecting = false
                await WebSocketStateManager.shared.setState(.connected)
                logger.info("Websocket connection established to \(host):\(port)")
            } catch {
                logger.warning("Websocket connect failed: \(error.localizedDescription)")
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
                try await channel.writeAndFlush(frame)
                return .success("Message sent successfully")
            } catch {
                logger.warning("Failed to send message: \(error.localizedDescription)")
                await handleClose()
                return .failure(
                    .websocketError("Failed to send message: \(error.localizedDescription)"))
            }
        }

        private func decodeIncomingMessage(_ data: Data) {
            logger.debug("Attempting to decode an incoming message from the websocket")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                let commandDTO = try decoder.decode(BasicCommandDTO.self, from: data)
                logger.debug("Incoming command: \(commandDTO.command)")
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
                    logger.warning("Unknown message type: \(commandDTO.command), data: \(data)")
                }

            } catch {
                logger.error(
                    "Error decoding message: \(error.localizedDescription), details: \(error)")
                let payloadString: String
                if let utf8 = String(data: data, encoding: .utf8) {
                    payloadString = utf8
                } else {
                    payloadString = data.base64EncodedString()
                }
                let preview = payloadString.prefix(2048)
                logger.error("Offending payload (utf8 if possible, else base64): \(preview)")
            }
        }

        private func writeFrame(_ frame: WebSocketFrame) {
            channel?.writeAndFlush(frame, promise: nil)
        }

        private func scheduleReconnect() async {
            guard !isConnecting else { return }
            reconnectAttempt += 1
            let delay = min(pow(2.0, Double(reconnectAttempt)), 30)
            logger.info("Scheduling websocket reconnect in \(String(format: "%.1f", delay))s")
            try? await Task.sleep(for: .seconds(Int(delay)))
            guard shouldStayConnected else { return }
            isConnecting = false
            connect()
        }
    }

    private final class HTTPInitialRequestHandler: ChannelInboundHandler {
        typealias InboundIn = HTTPClientResponsePart
        typealias OutboundOut = HTTPClientRequestPart

        private let host: String
        private let port: Int
        private let path: String
        private let headers: [String: String]

        init(host: String, port: Int, path: String, headers: [String: String]) {
            self.host = host
            self.port = port
            self.path = path
            self.headers = headers
        }

        func channelActive(context: ChannelHandlerContext) {
            var head = HTTPRequestHead(version: .http1_1, method: .GET, uri: path)
            let hostHeader = port == 80 || port == 443 ? host : "\(host):\(port)"
            head.headers.add(name: "Host", value: hostHeader)
            head.headers.add(name: "Connection", value: "Upgrade")
            head.headers.add(name: "Upgrade", value: "websocket")
            head.headers.add(name: "Sec-WebSocket-Version", value: "13")
            head.headers.add(
                name: "Sec-WebSocket-Key", value: NIOWebSocketClientUpgrader.randomRequestKey())
            for (key, value) in headers {
                head.headers.add(name: key, value: value)
            }

            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }

    private final class WebSocketFrameHandler: ChannelDuplexHandler {
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
                await owner?.handleFrame(frame)
            }
        }

        func channelInactive(context: ChannelHandlerContext) {
            Task { [weak owner] in
                await owner?.handleClose()
            }
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            Task { [weak owner] in
                owner?.logger.warning("Websocket channel error: \(error.localizedDescription)")
                await owner?.handleClose()
            }
            context.close(promise: nil)
        }
    }
#endif
