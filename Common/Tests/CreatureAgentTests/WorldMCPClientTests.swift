import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing
import WorldCore

@testable import creature_agent

@Suite("The mind's hand on WorldMCP")
struct WorldMCPClientTests {
    @Test(
        "tools/list becomes definitions; tools/call returns the text; a refusal throws; long answers are cut"
    )
    func listsCallsAndCuts() async throws {
        let router = Router(context: BasicRequestContext.self)
        router.post("world/mcp") { request, _ in
            let body = try await request.body.collect(upTo: 65_536)
            let call = try WorldJSON.makeDecoder().decode(
                WorldJSONValue.self, from: Data(buffer: body))
            #expect(call["jsonrpc"] == .string("2.0"))
            let answer: WorldJSONValue
            switch call["method"]?.stringValue {
            case "tools/list":
                answer = .object([
                    "result": .object([
                        "tools": .array([
                            .object([
                                "name": .string("query_entity"),
                                "description": .string("One entity, whole."),
                                "inputSchema": .object(["type": .string("object")]),
                            ]),
                            .object(["name": .string("nameless_schema")]),
                        ])
                    ])
                ])
            case "tools/call":
                let name = call["params"]?["name"]?.stringValue ?? ""
                let arguments = call["params"]?["arguments"] ?? .null
                switch name {
                case "query_entity":
                    #expect(arguments["entity_id"] == .string("person:jesse"))
                    answer = .object([
                        "result": .object([
                            "content": .array([
                                .object([
                                    "type": .string("text"), "text": .string("{\"facts\":[]}"),
                                ])
                            ])
                        ])
                    ])
                case "long":
                    answer = .object([
                        "result": .object([
                            "content": .array([
                                .object([
                                    "type": .string("text"),
                                    "text": .string(String(repeating: "x", count: 20_000)),
                                ])
                            ])
                        ])
                    ])
                default:
                    answer = .object([
                        "error": .object([
                            "code": .number(-32602), "message": .string("no such tool: \(name)"),
                        ])
                    ])
                }
            default:
                answer = .object(["error": .object(["code": .number(-32601)])])
            }
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: .init(
                    byteBuffer: ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(answer))))
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await httpClient.shutdown() } }
            let mcp = WorldMCPClient(
                url: URL(string: "http://localhost:\(port)/world/mcp")!, client: httpClient,
                logger: Logger(label: "mcp-tests"))

            let tools = try await mcp.listTools()
            #expect(tools.map(\.name) == ["query_entity", "nameless_schema"])
            #expect(tools[0].description == "One entity, whole.")
            #expect(tools[0].inputSchema == .object(["type": .string("object")]))
            #expect(tools[1].inputSchema["type"] == .string("object"))

            let answer = try await mcp.call(
                "query_entity", arguments: #"{"entity_id":"person:jesse"}"#)
            #expect(answer == "{\"facts\":[]}")

            await #expect(throws: WorldMCPClient.Failure.self) {
                try await mcp.call("drop_the_database", arguments: "{}")
            }
            let cut = try await mcp.call("long", arguments: "")
            #expect(cut.count < 16_100)
            #expect(cut.hasSuffix("ask again with a smaller limit]"))
        }
    }
}
