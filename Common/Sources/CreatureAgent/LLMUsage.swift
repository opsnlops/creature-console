import Foundation
import Logging
import Metrics
import Tracing

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
    /// The provider's `usage` object as it came, for the record: when the cached count reads
    /// zero on a prefix that cannot have missed, this says whether the field was there.
    var raw: String = ""

    var uncachedTokens: Int { max(0, inputTokens - cachedTokens) }
}

/// Which kind of call is under way, set by the mind around a model call and read by the
/// client that sees the provider's answer, so the record needs no new parameter on every
/// path between them. A child task inherits it; the streaming client's task is one.
enum LLMCallKind: String, Sendable {
    /// April's question, answered alone (the Communicator path).
    case question
    /// A turn in a scene April opened with her words.
    case scene
    /// A remark the house asked for, or a reaction to one.
    case house
    /// The nightly memory: the day's episodes, then the month's beliefs.
    case memory

    @TaskLocal static var current: LLMCallKind?
}

/// Records a call's usage on its span, as metrics, and in the log.
enum LLMUsageRecord {
    static func record(
        _ usage: LLMUsage, on span: any Span, model: String, kind: LLMCallKind?, round: Int,
        toolsOffered: Int, logger: Logger
    ) {
        let kindName = kind?.rawValue ?? "unknown"
        span.attributes["llm.usage.input_tokens"] = usage.inputTokens
        span.attributes["llm.usage.cached_tokens"] = usage.cachedTokens
        span.attributes["llm.usage.uncached_tokens"] = usage.uncachedTokens
        span.attributes["llm.usage.output_tokens"] = usage.outputTokens
        span.attributes["llm.call_kind"] = kindName
        span.attributes["llm.round"] = round
        span.attributes["llm.tools.offered"] = toolsOffered
        for (token, count) in [
            ("input", usage.inputTokens), ("cached", usage.cachedTokens),
            ("output", usage.outputTokens),
        ] where count > 0 {
            Counter(
                label: "creature_agent.llm.tokens",
                dimensions: [("token", token), ("kind", kindName), ("model", model)]
            ).increment(by: count)
        }
        logger.info(
            "LLM usage",
            metadata: [
                "llm.call_kind": "\(kindName)", "llm.model": "\(model)",
                "llm.usage.input_tokens": "\(usage.inputTokens)",
                "llm.usage.cached_tokens": "\(usage.cachedTokens)",
                "llm.usage.output_tokens": "\(usage.outputTokens)", "llm.round": "\(round)",
                "llm.usage.raw": "\(usage.raw)",
            ])
    }
}
