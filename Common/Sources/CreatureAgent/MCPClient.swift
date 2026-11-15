import AsyncHTTPClient
import Foundation
import Logging
import Metrics
import NIOCore
import Observability
import WorldCore

/// The mind's own hand on an MCP server - WorldMCP, and April's agent-memory (#294):
/// `tools/list`, so the model's tools are whatever the server offers and nothing is defined
/// twice, and `tools/call` when the model asks. JSON-RPC 2.0 over one POST each. WorldMCP
/// serves stateless Streamable HTTP; agent-memory wants a session (`session`), opened with
/// `initialize`, named in every later request's `Mcp-Session-Id`, and answers as an event
/// stream. Either way the server stays on the LAN: the model never reaches it, the mind does.
struct MCPClient: Sendable {
    struct ToolDefinition: Sendable, Equatable {
        var name: String
        var description: String
        /// The JSON schema of the arguments, as the server lists it.
        var inputSchema: WorldJSONValue
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String
        /// The JSON-RPC error code, when the server answered with one.
        var code: Int? = nil
        /// What kind of failure, low-cardinality, for `error.type`.
        var kind = "_OTHER"
    }

    let url: URL
    let client: HTTPClient
    let logger: Logger
    /// The mind asking, so the world can tell its own memories from another bird's private
    /// ones (#243). Nil, and the world shows it no bird's private memory.
    var mind: EntityID? = nil
    /// Who is asking, in `_meta.audience`: the world keeps its world-only facts from a mind.
    /// Nil for a server that is not the world and has no audiences.
    var audience: FactAudience? = .minds
    /// The server's name in errors: "WorldMCP answered 503 to tools/list".
    var serverName = "WorldMCP"
    /// Set for a server that keeps sessions (agent-memory); nil for stateless WorldMCP.
    var session: MCPSession? = nil

    /// The protocol revision this client speaks, sent in `initialize` and, for a session,
    /// in every later request's `MCP-Protocol-Version`.
    static let protocolVersion = "2025-06-18"

    /// A tool's answer is for the model, and the model's context is April's money: past this
    /// many characters the answer is cut with a note, and the model can ask again with a
    /// smaller limit.
    static let maximumOutputCharacters = 16_000

    func listTools() async throws -> [ToolDefinition] {
        let result = try await rpc("tools/list", params: .object([:]))
        guard case .array(let listed)? = result["tools"] else {
            throw Failure(description: "tools/list answered without tools")
        }
        return listed.compactMap { tool in
            guard case .string(let name)? = tool["name"] else { return nil }
            return ToolDefinition(
                name: name,
                description: tool["description"]?.stringValue ?? "",
                inputSchema: tool["inputSchema"]
                    ?? .object(["type": .string("object"), "properties": .object([:])]))
        }
    }

    /// Calls a tool with the model's arguments (a JSON object as text) and returns what the
    /// server said, as text for the model. A tool error is thrown with the server's words.
    func call(_ name: String, arguments: String) async throws -> String {
        let parsed: WorldJSONValue
        if arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsed = .object([:])
        } else {
            parsed = try WorldJSON.makeDecoder().decode(
                WorldJSONValue.self, from: Data(arguments.utf8))
        }
        // A mind is a mind: the world keeps what is for the world alone out of the answer, and
        // another bird's memory out unless that bird shared it.
        var meta: [String: WorldJSONValue] = [:]
        if let audience { meta["audience"] = .string(audience.rawValue) }
        if let mind, audience != nil { meta["mind"] = .string(mind.rawValue) }
        let result = try await rpc(
            "tools/call",
            params: .object(["name": .string(name), "arguments": parsed, "_meta": .object(meta)]),
            tool: name)
        if case .bool(true)? = result["isError"] {
            GenAI.toolSpan?.attributes[MCPTelemetry.Key.errorType] = "tool_error"
            throw Failure(description: Self.text(of: result), kind: "tool_error")
        }
        let text = Self.text(of: result)
        guard text.count > Self.maximumOutputCharacters else { return text }
        return String(text.prefix(Self.maximumOutputCharacters))
            + " …[cut here: ask again with a smaller limit]"
    }

    /// The text the server put in `content`, or the structured result as JSON.
    private static func text(of result: WorldJSONValue) -> String {
        if case .array(let content)? = result["content"] {
            let texts = content.compactMap { $0["text"]?.stringValue }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        if let structured = result["structuredContent"],
            let data = try? WorldJSON.makeEncoder().encode(structured)
        {
            return String(decoding: data, as: UTF8.self)
        }
        return "{}"
    }

    /// One JSON-RPC request, traced by the MCP conventions: a `tools/call` is described on the
    /// `execute_tool` span already covering it; anything else (`tools/list`) gets a CLIENT span
    /// of its own. Either way the trace rides in `params._meta`, so the world's span for the
    /// call is this one's child.
    private func rpc(_ method: String, params: WorldJSONValue, tool: String? = nil)
        async throws -> WorldJSONValue
    {
        let started = ContinuousClock.now
        var failure: String?
        defer {
            var dimensions = [("unit", "s"), (MCPTelemetry.Key.methodName, method)]
            if let tool { dimensions.append((MCPTelemetry.Key.toolName, tool)) }
            if let failure { dimensions.append((MCPTelemetry.Key.errorType, failure)) }
            Timer(label: MCPTelemetry.Metric.clientOperationDuration, dimensions: dimensions)
                .record(duration: ContinuousClock.now - started)
        }
        func traced(_ span: any Span) async throws -> WorldJSONValue {
            describe(span, method: method, tool: tool)
            do {
                return try await send(method, params: params)
            } catch {
                let failed = error as? Failure
                failure = failed?.kind ?? String(describing: type(of: error))
                span.attributes[MCPTelemetry.Key.errorType] = failure
                span.attributes[MCPTelemetry.Key.rpcResponseStatusCode] = failed?.code.map {
                    "\($0)"
                }
                throw error
            }
        }
        if method == "tools/call", let span = GenAI.toolSpan {
            return try await traced(span)
        }
        return try await withSpan(
            MCPTelemetry.spanName(method: method, tool: tool), ofKind: .client
        ) { span in
            try await traced(span)
        }
    }

    private func describe(_ span: any Span, method: String, tool: String?) {
        span.attributes[MCPTelemetry.Key.methodName] = method
        span.attributes[MCPTelemetry.Key.jsonRPCRequestID] = "1"
        span.attributes[MCPTelemetry.Key.networkTransport] = "tcp"
        span.attributes[MCPTelemetry.Key.networkProtocolName] = "http"
        span.attributes[MCPTelemetry.Key.serverAddress] = url.host
        span.attributes[MCPTelemetry.Key.serverPort] =
            url.port ?? (url.scheme == "https" ? 443 : 80)
        if let tool {
            span.attributes[MCPTelemetry.Key.toolName] = tool
            span.attributes[MCPTelemetry.Key.operationName] = "execute_tool"
        }
    }

    private func send(_ method: String, params: WorldJSONValue) async throws -> WorldJSONValue {
        guard let session else { return try await post(method, params: params, sessionID: nil) }
        let id = try await session.id { try await open() }
        do {
            return try await post(method, params: params, sessionID: id)
        } catch let failure as Failure where failure.kind == "404" || failure.kind == "400" {
            // The server no longer knows the session (it restarted, or let it go): a new one,
            // once. 404 is the spec's answer; agent-memory says 400 "Session ID is required".
            await session.forget(id)
            let fresh = try await session.id { try await open() }
            return try await post(method, params: params, sessionID: fresh)
        }
    }

    /// Opens a session: `initialize`, whose answer names the session in `Mcp-Session-Id`,
    /// then `notifications/initialized` under that name.
    private func open() async throws -> String {
        let initialize = WorldJSONValue.object([
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string("creature-agent"),
                "version": .string(CreatureAgent.configuration.version),
            ]),
        ])
        let answer = try await exchange(
            try request("initialize", params: initialize), sessionID: nil, method: "initialize")
        guard let id = answer.sessionID, !id.isEmpty else {
            throw Failure(description: "\(serverName) opened no session", kind: "no_session")
        }
        _ = try await exchange(
            try request("notifications/initialized", params: nil), sessionID: id,
            method: "notifications/initialized")
        logger.debug("Opened an MCP session", metadata: ["mcp.url": "\(url.absoluteString)"])
        return id
    }

    private func post(_ method: String, params: WorldJSONValue, sessionID: String?)
        async throws -> WorldJSONValue
    {
        let answer = try await exchange(
            try request(method, params: Self.carryingTheTrace(params)), sessionID: sessionID,
            method: method)
        let bytes = answer.body
        let envelope: WorldJSONValue
        if answer.contentType?.lowercased().hasPrefix("text/event-stream") == true {
            guard
                let found = Self.envelope(
                    fromEventStream: String(decoding: bytes.readableBytesView, as: UTF8.self))
            else {
                throw Failure(description: "\(serverName) streamed no answer to \(method)")
            }
            envelope = found
        } else {
            envelope = try WorldJSON.makeDecoder().decode(
                WorldJSONValue.self, from: Data(bytes.readableBytesView))
        }
        if let error = envelope["error"] {
            let code: Int? =
                if case .number(let number)? = error["code"] { Int(number) } else { nil }
            throw Failure(
                description: error["message"]?.stringValue ?? "\(serverName) refused \(method)",
                code: code, kind: code.map { "\($0)" } ?? "_OTHER")
        }
        guard let result = envelope["result"] else {
            throw Failure(description: "\(serverName) answered \(method) without a result")
        }
        return result
    }

    /// A JSON-RPC request; without params and an id when it is a notification.
    private func request(_ method: String, params: WorldJSONValue?) throws -> Data {
        var fields: [String: WorldJSONValue] = [
            "jsonrpc": .string("2.0"), "method": .string(method),
        ]
        if let params {
            fields["id"] = .number(1)
            fields["params"] = params
        }
        return try WorldJSON.makeEncoder().encode(WorldJSONValue.object(fields))
    }

    /// One POST; anything but 200 (or 202, a notification's answer) throws with the status.
    private func exchange(_ body: Data, sessionID: String?, method: String)
        async throws -> (contentType: String?, sessionID: String?, body: ByteBuffer)
    {
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        if session == nil {
            request.headers.add(name: "Accept", value: "application/json")
        } else {
            // The spec asks a client to accept both; agent-memory answers as a stream.
            request.headers.add(name: "Accept", value: "application/json, text/event-stream")
        }
        if let sessionID {
            request.headers.add(name: "Mcp-Session-Id", value: sessionID)
            request.headers.add(name: "MCP-Protocol-Version", value: Self.protocolVersion)
        }
        request.body = .bytes(body)
        let response = try await client.execute(request, timeout: .seconds(20), logger: logger)
        let bytes = try await response.body.collect(upTo: 8 * 1_048_576)
        guard response.status == .ok || response.status == .accepted else {
            throw Failure(
                description: "\(serverName) answered \(response.status.code) to \(method)",
                kind: "\(response.status.code)")
        }
        return (
            response.headers.first(name: "Content-Type"),
            response.headers.first(name: "Mcp-Session-Id"), bytes
        )
    }

    /// The JSON-RPC answer in a Server-Sent Events body: the last `data:` payload that is a
    /// response (a `result` or an `error`), past the priming event and any notifications.
    static func envelope(fromEventStream text: String) -> WorldJSONValue? {
        var events: [String] = []
        var current: [String] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.isEmpty {
                if !current.isEmpty { events.append(current.joined(separator: "\n")) }
                current = []
            } else if line.hasPrefix("data:") {
                var payload = line.dropFirst(5)
                if payload.first == " " { payload = payload.dropFirst() }
                current.append(String(payload))
            }
        }
        if !current.isEmpty { events.append(current.joined(separator: "\n")) }
        let decoder = WorldJSON.makeDecoder()
        return events.reversed().lazy.compactMap { event -> WorldJSONValue? in
            guard
                let value = try? decoder.decode(WorldJSONValue.self, from: Data(event.utf8)),
                value["result"] != nil || value["error"] != nil
            else { return nil }
            return value
        }.first
    }

    /// The params with the current trace in `_meta` (`traceparent`, `tracestate`), beside
    /// whatever `_meta` already said.
    static func carryingTheTrace(
        _ params: WorldJSONValue, headers: [String: String] = currentTraceHeaders()
    ) -> WorldJSONValue {
        guard !headers.isEmpty, case .object(var fields) = params else { return params }
        var meta: [String: WorldJSONValue] = [:]
        if case .object(let held)? = fields["_meta"] { meta = held }
        for (key, value) in headers where MCPTelemetry.traceKeys.contains(key) {
            meta[key] = .string(value)
        }
        fields["_meta"] = .object(meta)
        return .object(fields)
    }
}

extension WorldJSONValue {
    subscript(key: String) -> WorldJSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }
    var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }
}

/// A session with a server that keeps them (agent-memory): opened once, on first use, and
/// shared by every call; calls that arrive while it is opening wait for the one opening
/// rather than each opening their own. `forget` drops a session the server no longer knows,
/// so the next call opens another.
actor MCPSession {
    private var opening: Task<String, any Error>?

    func id(_ open: @escaping @Sendable () async throws -> String) async throws -> String {
        let task = opening ?? Task { try await open() }
        opening = task
        do {
            return try await task.value
        } catch {
            // A failed opening is not kept: the next call tries again.
            if opening == task { opening = nil }
            throw error
        }
    }

    func forget(_ id: String) async {
        guard let opening, (try? await opening.value) == id else { return }
        if self.opening == opening { self.opening = nil }
    }
}
