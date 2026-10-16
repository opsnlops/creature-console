import Foundation

/// What a model call cost, as the provider reports it, and what kind of call it was - so the
/// cost of a question, a scene turn, a house remark, and a night's memory can each be seen on
/// its own. April: "This is getting expensive to run because of the number of input tokens
/// we're burning." Measured first, trimmed second.
struct LLMUsage: Sendable, Equatable {
    var inputTokens: Int
    /// The part of the input the provider served from its prompt cache (already counted in
    /// `inputTokens`; billed at a fraction).
    var cachedTokens: Int
    var outputTokens: Int
    /// The part of the output spent reasoning (already counted in `outputTokens`).
    var reasoningTokens: Int = 0
    /// The provider's `usage` object as it came, for the record: when the cached count reads
    /// zero on a prefix that cannot have missed, this says whether the field was there.
    var raw: String = ""

    var uncachedTokens: Int { max(0, inputTokens - cachedTokens) }
}

/// Which kind of call is under way - on every GenAI span and metric as
/// `creature_agent.call_kind`, carried from the mind to the client by `GenAI.turn`.
enum LLMCallKind: String, Sendable {
    /// April's question, answered alone (the Communicator path).
    case question
    /// A turn in a scene April opened with her words.
    case scene
    /// A remark the house asked for, or a reaction to one.
    case house
    /// The nightly memory: the day's episodes, then the month's beliefs.
    case memory
}
