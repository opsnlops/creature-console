import Foundation

/// What a mind may reach for beyond its envelope: the world, over WorldMCP, as tools the model
/// calls for itself. The Responses API calls the server directly - the mind never sees the
/// traffic, only the answer - so a look-up costs the model a round trip and April nothing.
/// Read only: WorldMCP has no write tools. Passed with a prompt when the moment allows a
/// look-up (a question from April) and left off a house remark, which must be quick.
///
/// April: "As the knowledge in the world grows we're quickly going to hit the limit of what
/// we can pre-emptively send in the context to the agent." Tools are the way past it: the
/// envelope carries what a moment needs; the model fetches the rest when a question calls
/// for it.
struct ModelTools: Sendable {
    /// One tool the model called, as the stream reported it, for the record.
    struct Call: Sendable, Equatable {
        var server: String
        var name: String
        var arguments: String
        var output: String?
        var error: String?
    }

    /// The MCP server's label in the prompt and the record: "world".
    var serverLabel: String
    var serverURL: URL
    /// The tools the model may call; the server offers more than a mind should be tempted by.
    var allowedTools: [String]
    /// Told of every call the model makes, so the world can record it.
    var onCall: @Sendable (Call) async -> Void

    static let defaultAllowedTools = [
        "query_entity", "query_day", "query_timeline", "query_scenes", "query_conversation",
        "query_timers", "query_glossary", "explain_fact", "inspect_world_state",
    ]

    /// What the contract tells the model about them.
    static let contract = """
        You have tools that look things up in the world - who someone is, what happened on a \
        day or lately, what is scheduled, why a fact is what it is. Use one when a question of \
        April's needs more than what you know below; never for a passing remark, and never to \
        check what is already written here. Say what you found in your own words, briefly.
        """
}
