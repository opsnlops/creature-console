import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
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
    }

    let url: URL
    let client: HTTPClient
    let logger: Logger

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
        let result = try await rpc(
            "tools/call", params: .object(["name": .string(name), "arguments": parsed]))
        if case .bool(true)? = result["isError"] {
            throw Failure(description: Self.text(of: result))
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

    private func rpc(_ method: String, params: WorldJSONValue) async throws -> WorldJSONValue {
        let body = try WorldJSON.makeEncoder().encode(
            WorldJSONValue.object([
                "jsonrpc": .string("2.0"), "id": .number(1), "method": .string(method),
                "params": params,
            ]))
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Accept", value: "application/json")
        request.body = .bytes(body)
        let response = try await client.execute(request, timeout: .seconds(20), logger: logger)
        let bytes = try await response.body.collect(upTo: 8 * 1_048_576)
        guard response.status == .ok else {
            throw Failure(description: "WorldMCP answered \(response.status.code) to \(method)")
        }
        let envelope = try WorldJSON.makeDecoder().decode(
            WorldJSONValue.self, from: Data(bytes.readableBytesView))
        if let error = envelope["error"] {
            throw Failure(
                description: error["message"]?.stringValue ?? "WorldMCP refused \(method)")
        }
        guard let result = envelope["result"] else {
            throw Failure(description: "WorldMCP answered \(method) without a result")
        }
        return result
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
