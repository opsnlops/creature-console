import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing
import WorldCore

@testable import creature_agent

extension ToolServer {
    /// A server with no tools, for tests that only need one to be there.
    static func stub(label: String, contract: String = ToolServer.worldContract) -> ToolServer {
        ToolServer(label: label, contract: contract, catalogue: { [] }, call: { _, _ in "" })
    }
}

extension ModelTools {
    /// One server's worth of tools, for tests of the round trip.
    static func single(
        label: String, catalogue: @escaping @Sendable () async -> [MCPClient.ToolDefinition],
        call: @escaping @Sendable (String, String) async throws -> String,
        onCall: @escaping @Sendable (Call) async -> Void
    ) -> ModelTools {
        ModelTools(
            servers: [
                ToolServer(
                    label: label, contract: ToolServer.worldContract, catalogue: catalogue,
                    call: call)
            ], onCall: onCall)
    }
}

@Suite("April's project notebook as read-only tools (#294)")
struct AgentMemoryToolsTests {
    @Test("The answer in an event stream is the response, past the priming event")
    func readsTheEventStream() throws {
        let stream = """
            data: 
            id: 0
            retry: 3000

            data: {"jsonrpc":"2.0","method":"notifications/message","params":{}}

            data: {"jsonrpc":"2.0","id":1,"result":{"tools":[]}}


            """
        let envelope = try #require(MCPClient.envelope(fromEventStream: stream))
        #expect(envelope["result"]?["tools"] == .array([]))
        #expect(MCPClient.envelope(fromEventStream: "data: \nid: 0\n\n") == nil)
        // CRLF line endings are a stream too.
        #expect(
            MCPClient.envelope(
                fromEventStream: "data: {\"id\":1,\"error\":{\"code\":-1}}\r\n\r\n")?["error"]
                != nil)
    }

    @Test(
        "A session is opened once, named in every call, reopened when the server forgets it; only read tools are offered, renamed; writes never leave the mind"
    )
    func sessionsAndReadOnly() async throws {
        let server = NotebookServer()
        let router = Router(context: BasicRequestContext.self)
        router.post("mcp") { request, _ in
            let session = request.headers[.init("Mcp-Session-Id")!]
            let body = try await request.body.collect(upTo: 65_536)
            let call = try WorldJSON.makeDecoder().decode(
                WorldJSONValue.self, from: Data(buffer: body))
            return try await server.answer(call, session: session)
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await httpClient.shutdown() } }
            let logger = Logger(label: "agent-memory-tests")
            let mcp = MCPClient(
                url: URL(string: "http://localhost:\(port)/mcp")!, client: httpClient,
                logger: logger, mind: try EntityID(validating: "character:mango"), audience: nil,
                serverName: "agent-memory", session: MCPSession())
            let (notebook, _) = ToolServer.agentMemory(mcp, logger: logger)
            let tools = ModelTools(servers: [notebook], onCall: { _ in })

            // Only the read tools, under names that cannot be mistaken for the world's.
            let offered = await tools.catalogue()
            #expect(
                offered.map(\.name).sorted() == [
                    "agent_memory_get", "agent_memory_list_tags", "agent_memory_search",
                ])
            #expect(offered.allSatisfy { $0.description.hasPrefix("April's project notebook") })
            #expect(tools.contract.contains("April's project notebook"))

            let found = try await tools.call(
                "agent_memory_search", arguments: #"{"query":"projects"}"#)
            #expect(found.contains("Project state: creature-console"))

            // Write tools are refused here: not one request reaches the server for them.
            let before = await server.calls
            for name in ["agent_memory_remember", "remember", "agent_memory_forget", "forget"] {
                await #expect(throws: ModelTools.UnknownTool.self) {
                    try await tools.call(name, arguments: #"{"title":"x","body":"y"}"#)
                }
            }
            #expect(await server.calls == before)

            // The server restarts and forgets every session: the next call opens a new one.
            await server.restart()
            let again = try await tools.call("agent_memory_get", arguments: #"{"id":"abc"}"#)
            #expect(again.contains("Current status"))

            #expect(await server.sessionsOpened == 2)
            #expect(await server.toolsCalled == ["search", "get"])
            // No world audience rides along to a server that has none.
            #expect(await server.sawAudience == false)
        }
    }

    @Test("With both servers, the model gets both catalogues and both contracts; calls route")
    func bothServers() async throws {
        let routed = Routed()
        let tools = ModelTools(
            servers: [
                ToolServer(
                    label: "world", contract: ToolServer.worldContract,
                    catalogue: {
                        [.init(name: "search_world", description: "", inputSchema: .object([:]))]
                    },
                    call: { name, _ in
                        await routed.note("world:\(name)")
                        return "{}"
                    }),
                ToolServer(
                    label: "agent_memory", contract: ToolServer.agentMemoryContract,
                    catalogue: {
                        [
                            .init(
                                name: "agent_memory_search", description: "",
                                inputSchema: .object([:]))
                        ]
                    },
                    call: { name, _ in
                        await routed.note("agent_memory:\(name)")
                        return "{}"
                    }),
            ], onCall: { _ in })

        #expect(
            await tools.catalogue().map(\.name) == ["search_world", "agent_memory_search"])
        #expect(tools.contract.contains("look things up in the world"))
        #expect(tools.contract.contains("April's project notebook"))
        _ = try await tools.call("agent_memory_search", arguments: "{}")
        _ = try await tools.call("search_world", arguments: "{}")
        #expect(await tools.server(offering: "agent_memory_search")?.label == "agent_memory")
        #expect(await routed.names == ["agent_memory:agent_memory_search", "world:search_world"])
    }
}

private actor Routed {
    private(set) var names: [String] = []
    func note(_ name: String) { names.append(name) }
}

/// A stand-in for agent-memory: sessions in headers, answers as an event stream, 400 for a
/// call with no session (its real words) and 404 for a session it does not know.
private actor NotebookServer {
    private var sessions: Set<String> = []
    private(set) var sessionsOpened = 0
    private(set) var calls = 0
    private(set) var toolsCalled: [String] = []
    private(set) var sawAudience = false

    func restart() { sessions.removeAll() }

    func answer(_ call: WorldJSONValue, session: String?) throws -> Response {
        calls += 1
        let method = call["method"]?.stringValue ?? ""
        if method == "initialize" {
            #expect(call["params"]?["protocolVersion"] == .string(MCPClient.protocolVersion))
            sessionsOpened += 1
            let id = UUID().uuidString
            sessions.insert(id)
            return stream(
                .object(["serverInfo": .object(["name": .string("agent-memory")])]),
                session: id)
        }
        guard let session else {
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(string: "Bad Request: Session ID is required")))
        }
        guard sessions.contains(session) else { return Response(status: .notFound) }
        if method == "notifications/initialized" { return Response(status: .accepted) }
        if call["params"]?["_meta"]?["audience"] != nil { sawAudience = true }
        switch method {
        case "tools/list":
            let names = ["edit", "forget", "get", "list_tags", "remember", "search", "update"]
            return stream(
                .object([
                    "tools": .array(
                        names.map {
                            .object([
                                "name": .string($0), "description": .string("The \($0) tool."),
                                "inputSchema": .object(["type": .string("object")]),
                            ])
                        })
                ]))
        case "tools/call":
            let name = call["params"]?["name"]?.stringValue ?? ""
            toolsCalled.append(name)
            let text =
                name == "search"
                ? #"{"results":[{"title":"Project state: creature-console"}]}"#
                : #"{"title":"Project state","headings":["Current status"]}"#
            return stream(
                .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])])
                ]))
        default:
            return stream(nil)
        }
    }

    private func stream(_ result: WorldJSONValue?, session: String? = nil) -> Response {
        var envelope: [String: WorldJSONValue] = ["jsonrpc": .string("2.0"), "id": .number(1)]
        if let result {
            envelope["result"] = result
        } else {
            envelope["error"] = .object(["code": .number(-32601)])
        }
        let json = String(
            decoding: (try? WorldJSON.makeEncoder().encode(WorldJSONValue.object(envelope)))
                ?? Data(), as: UTF8.self)
        var headers: HTTPFields = [.contentType: "text/event-stream"]
        if let session { headers[.init("Mcp-Session-Id")!] = session }
        return Response(
            status: .ok, headers: headers,
            body: .init(
                byteBuffer: ByteBuffer(string: "data: \nid: 0\nretry: 3000\n\ndata: \(json)\n\n")))
    }
}
