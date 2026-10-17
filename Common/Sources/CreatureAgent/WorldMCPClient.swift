import AsyncHTTPClient
import Foundation
import Logging
import Metrics
import NIOCore
import Observability
import WorldCore

/// The mind's own hand on WorldMCP: `tools/list` once at startup, so the model's tools are
/// whatever the world offers and nothing is defined twice, and `tools/call` when the model
/// asks. Plain JSON-RPC 2.0 over one POST each - stateless Streamable HTTP, the way the world
/// serves it. The world stays on the LAN: the model never reaches it, the mind does.
struct WorldMCPClient: Sendable {
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
        var meta: [String: WorldJSONValue] = ["audience": .string(FactAudience.minds.rawValue)]
        if let mind { meta["mind"] = .string(mind.rawValue) }
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
        let body = try WorldJSON.makeEncoder().encode(
            WorldJSONValue.object([
                "jsonrpc": .string("2.0"), "id": .number(1), "method": .string(method),
                "params": Self.carryingTheTrace(params),
            ]))
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Accept", value: "application/json")
        request.body = .bytes(body)
        let response = try await client.execute(request, timeout: .seconds(20), logger: logger)
        let bytes = try await response.body.collect(upTo: 8 * 1_048_576)
        guard response.status == .ok else {
            throw Failure(
                description: "WorldMCP answered \(response.status.code) to \(method)",
                kind: "\(response.status.code)")
        }
        let envelope = try WorldJSON.makeDecoder().decode(
            WorldJSONValue.self, from: Data(bytes.readableBytesView))
        if let error = envelope["error"] {
            let code: Int? =
                if case .number(let number)? = error["code"] { Int(number) } else { nil }
            throw Failure(
                description: error["message"]?.stringValue ?? "WorldMCP refused \(method)",
                code: code, kind: code.map { "\($0)" } ?? "_OTHER")
        }
        guard let result = envelope["result"] else {
            throw Failure(description: "WorldMCP answered \(method) without a result")
        }
        return result
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
