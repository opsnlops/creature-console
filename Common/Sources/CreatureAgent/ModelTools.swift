import Foundation
import Logging
import WorldCore

/// What a mind may reach for beyond its envelope: MCP servers on the LAN - the world, and
/// April's agent-memory (#294) - as tools the model asks for and the mind runs. The model
/// answers with a function call; the mind calls the server (the model never reaches it),
/// hands the answer back, and the model goes on. Read only: every server is offered only its
/// allowed tools, and a call to any other name is refused here, before it leaves the mind.
/// Passed with a prompt when the moment allows a look-up (a question from April) and left
/// off a house remark, which must be quick.
///
/// April: "As the knowledge in the world grows we're quickly going to hit the limit of what
/// we can pre-emptively send in the context to the agent." Tools are the way past it: the
/// envelope carries what a moment needs; the model fetches the rest when a question calls
/// for it.
struct ModelTools: Sendable {
    /// One tool the model called and the mind ran, for the record.
    struct Call: Sendable, Equatable {
        var server: String
        var name: String
        var arguments: String
        var output: String?
        var error: String?
    }

    /// A name the model asked for that no server offered it - a write tool, a guess.
    struct UnknownTool: Error, CustomStringConvertible {
        var name: String
        var description: String { "there is no tool called \(name)" }
    }

    /// The servers, in the order their tools are offered.
    var servers: [ToolServer]
    /// Told of every call the model makes, so the world can record it.
    var onCall: @Sendable (Call) async -> Void

    /// The tools the model is offered: every server's, asked for at each use, so a server
    /// that was still starting when the mind came up is not a server without tools for good.
    func catalogue() async -> [MCPClient.ToolDefinition] {
        var all: [MCPClient.ToolDefinition] = []
        for server in servers { all += await server.catalogue() }
        return all
    }

    /// The server offering `name`, or nil when none does.
    func server(offering name: String) async -> ToolServer? {
        for server in servers where await server.catalogue().contains(where: { $0.name == name }) {
            return server
        }
        return nil
    }

    /// Runs one tool: the name and the model's arguments (a JSON object as text) in, the
    /// server's answer as text out. A name no server offered is refused without a request.
    func call(_ name: String, arguments: String) async throws -> String {
        guard let server = await server(offering: name) else { throw UnknownTool(name: name) }
        return try await server.call(name, arguments)
    }

    /// What the contract tells the model about the tools it has.
    var contract: String { servers.map(\.contract).joined(separator: " ") }

    /// How many rounds of look-ups one answer may take before the model must speak.
    static let maximumRounds = 3
}

/// One MCP server's tools as the model sees them: a label for the record, the catalogue
/// (already filtered to what a mind may use, under the names the model is given), the call
/// (from those names), and the words the contract says about them.
struct ToolServer: Sendable {
    var label: String
    var contract: String
    var catalogue: @Sendable () async -> [MCPClient.ToolDefinition]
    var call: @Sendable (String, String) async throws -> String

    /// A server reached through `mcp`, offering only `allowed`, each under `prefix` + its own
    /// name (so agent-memory's `search` is the model's `agent_memory_search`), with
    /// `describe` rewriting each description for a mind.
    static func mcp(
        _ mcp: MCPClient, label: String, allowed: [String], prefix: String = "",
        contract: String, describe: @escaping @Sendable (String) -> String = { $0 },
        logger: Logger
    ) -> (server: ToolServer, catalogue: ToolCatalogue) {
        let catalogue = ToolCatalogue(
            mcp: mcp, allowed: Set(allowed), prefix: prefix, describe: describe, logger: logger)
        let server = ToolServer(
            label: label, contract: contract,
            catalogue: { await catalogue.definitions() },
            call: { name, arguments in
                guard name.hasPrefix(prefix) else { throw ModelTools.UnknownTool(name: name) }
                return try await mcp.call(
                    String(name.dropFirst(prefix.count)), arguments: arguments)
            })
        return (server, catalogue)
    }

    /// WorldMCP: the world's read tools under their own names.
    static func world(_ mcp: MCPClient, logger: Logger) -> (
        server: ToolServer, catalogue: ToolCatalogue
    ) {
        Self.mcp(
            mcp, label: "world", allowed: worldTools, contract: worldContract, logger: logger)
    }

    /// The world's tools a mind should be tempted by; the server offers more.
    static let worldTools = [
        "search_world", "query_entity", "query_day", "query_timeline", "query_scenes",
        "query_conversation", "query_timers", "query_glossary", "explain_fact",
        "inspect_world_state",
    ]

    /// What the contract tells the model about the world's tools.
    static let worldContract = """
        You have tools that look things up in the world - who someone is, what happened on a \
        day or lately, what is scheduled, why a fact is what it is. Use one when a question of \
        April's needs more than what you know below; never for a passing remark, and never to \
        check what is already written here. When you do not know who or what a name is, \
        search_world first. Ask for small limits. Say what you found in your own words, briefly. \
        Another bird's memories reach you only when that bird chose to share them; the rest are \
        theirs alone and never come back to you. One that does - memory.episode.caroll.… - is \
        still theirs: say it as theirs ("Caroll remembers…"), never as your own memory or as \
        something you saw yourself.
        """

    /// April's agent-memory (#294): the notes her coding agents keep on her projects, read
    /// only. `search`, `get` and `list_tags` are its read tools; `remember`, `update`, `edit`
    /// and `forget` are never offered, and a call to them is refused before it is sent.
    static func agentMemory(_ mcp: MCPClient, logger: Logger) -> (
        server: ToolServer, catalogue: ToolCatalogue
    ) {
        Self.mcp(
            mcp, label: "agent_memory", allowed: agentMemoryTools, prefix: agentMemoryPrefix,
            contract: agentMemoryContract,
            describe: { "April's project notebook (read only). " + $0 }, logger: logger)
    }

    static let agentMemoryTools = ["search", "get", "list_tags"]
    static let agentMemoryPrefix = "agent_memory_"

    /// What the contract tells the model about April's project notebook.
    static let agentMemoryContract = """
        You can also read April's project notebook: the notes her coding agents keep while \
        they build things with her - what each of her projects is, where it stands, what was \
        decided and why, what she has been researching lately. When April talks about her \
        projects or her work and the notebook would help, agent_memory_search it (a few plain \
        words; project names like creature-console), then agent_memory_get the one entry that \
        matters - a section at a time for a long one, such as "Current status". The notebook \
        is April's work, not the world: say what you read as what her notes say, in your own \
        words and briefly, never as something you saw or remember. You can only read it; \
        nothing you say is written there.
        """
}

/// One server's tool list, fetched when first needed and kept; a failure is retried after
/// `retryAfter`, so the mind never speaks without tools merely because the server restarted
/// a moment before it did. Only `allowed` tools are kept, renamed with `prefix`.
actor ToolCatalogue {
    private let mcp: MCPClient
    private let allowed: Set<String>
    private let prefix: String
    private let describe: @Sendable (String) -> String
    private let logger: Logger
    private var cached: [MCPClient.ToolDefinition] = []
    private var lastFailure: Date?
    private let retryAfter: TimeInterval

    init(
        mcp: MCPClient, allowed: Set<String>, prefix: String = "",
        describe: @escaping @Sendable (String) -> String = { $0 }, logger: Logger,
        retryAfter: TimeInterval = 30
    ) {
        self.mcp = mcp
        self.allowed = allowed
        self.prefix = prefix
        self.describe = describe
        self.logger = logger
        self.retryAfter = retryAfter
    }

    func definitions() async -> [MCPClient.ToolDefinition] {
        if !cached.isEmpty { return cached }
        if let lastFailure, Date().timeIntervalSince(lastFailure) < retryAfter { return [] }
        do {
            cached = try await mcp.listTools().filter { allowed.contains($0.name) }.map {
                var exposed = $0
                exposed.name = prefix + $0.name
                exposed.description = describe($0.description)
                return exposed
            }
            lastFailure = nil
            logger.info(
                "\(mcp.serverName) is at hand as tools",
                metadata: [
                    "mcp.url": "\(mcp.url.absoluteString)",
                    "mcp.tools": "\(cached.map(\.name).joined(separator: ","))",
                ])
        } catch {
            lastFailure = Date()
            logger.error(
                "\(mcp.serverName) would not list its tools; the mind answers without them for now",
                metadata: ["mcp.url": "\(mcp.url.absoluteString)", "error": "\(error)"])
        }
        return cached
    }
}
