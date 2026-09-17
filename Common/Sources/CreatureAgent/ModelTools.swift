import Foundation
import WorldCore

/// What a mind may reach for beyond its envelope: the world, over WorldMCP, as tools the model
/// asks for and the mind runs. The model answers with a function call; the mind calls the
/// world (on the LAN - the model never reaches it), hands the answer back, and the model goes
/// on. Read only: WorldMCP has no write tools. Passed with a prompt when the moment allows a
/// look-up (a question from April) and left off a house remark, which must be quick.
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

    /// The server's name in the record: "world".
    var serverLabel: String
    /// The tools the model is offered, as the server lists them.
    var definitions: [WorldMCPClient.ToolDefinition]
    /// Runs one tool: the name and the model's arguments (a JSON object as text) in, the
    /// server's answer as text out; throws with the server's words when the tool fails.
    var call: @Sendable (String, String) async throws -> String
    /// Told of every call the model makes, so the world can record it.
    var onCall: @Sendable (Call) async -> Void

    /// The tools a mind should be tempted by; the server offers more.
    static let defaultAllowedTools = [
        "query_entity", "query_day", "query_timeline", "query_scenes", "query_conversation",
        "query_timers", "query_glossary", "explain_fact", "inspect_world_state",
    ]

    /// How many rounds of look-ups one answer may take before the model must speak.
    static let maximumRounds = 3

    /// What the contract tells the model about them.
    static let contract = """
        You have tools that look things up in the world - who someone is, what happened on a \
        day or lately, what is scheduled, why a fact is what it is. Use one when a question of \
        April's needs more than what you know below; never for a passing remark, and never to \
        check what is already written here. Ask for small limits. Say what you found in your \
        own words, briefly.
        """
}
