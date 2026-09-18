import ArgumentParser
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// `creature-agent probe-cache`: learns the provider's prompt-cache rules without touching the
/// birds. The same stable prefix (a few thousand tokens of the same text) goes out three
/// times with a fresh "moment" line each time, the way a mind's prompts do, and the raw
/// `usage` of each answer is printed. On 2026-09-17 every live call wrote its whole input to
/// the cache and read nothing back - store, key, and tier made no difference - which is the
/// shape of a cache that stores blocks and needs to be told where the stable one ends. The
/// variants try that, one field at a time, so a wrong field is a 400 here and not a silent
/// Beaky.
struct ProbeCache: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-cache",
        abstract: "Send the same prefix three times and print the provider's raw usage")

    @Option(help: "The model, e.g. gpt-5.6-sol") var model: String
    @Option(help: "service_tier to send, if any (fast, priority, flex, default)")
    var tier: String?
    @Option(help: "Roughly how many tokens the stable prefix should be") var prefixTokens = 3_000
    @Option(help: "Send prompt_cache_key with this value") var key: String?
    @Flag(help: "Send store: true") var store = false
    @Option(help: "Send prompt_cache_retention, e.g. 24h") var retention: String?
    @Option(
        help:
            "Mark the stable item as a cache block with this field on the item, as JSON - e.g. '{\"cache_control\":{\"type\":\"ephemeral\"}}'"
    )
    var breakpoint: String?
    @Option(help: "Seconds between the three calls") var pause = 2
    @Option(help: "Send this many function tools with nested schemas, as a mind does")
    var tools = 0
    @Option(help: "Send reasoning: {effort: <this>}") var reasoning: String?
    @Flag(help: "Send text: {format: {type: text}}") var textFormat = false
    @Flag(help: "Stream, and read usage from response.completed, as a mind does") var stream = false
    @Option(help: "The endpoint") var endpoint = OpenAIClient.defaultEndpoint.absoluteString

    func run() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty
        else {
            throw ValidationError(
                "OPENAI_API_KEY is not set (source /etc/default/creature-agent-<instance>)")
        }
        // A deterministic prefix: the same words every run, long enough to be worth caching.
        let sentence =
            "The purple house on the hill keeps three birds, a printer, and a great many robot parts. "
        let repeats = max(1, prefixTokens / 20)
        let stable =
            "You are a helpful assistant in a test. Remember the following.\n\n"
            + String(repeating: sentence, count: repeats)
        var extra: [String: Any] = [:]
        if let breakpoint {
            guard let data = breakpoint.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw ValidationError("--breakpoint must be a JSON object") }
            extra = object
        }
        print(
            "prefix ≈ \(prefixTokens) tokens; model \(model); tier \(tier ?? "default"); key \(key ?? "none"); store \(store); retention \(retention ?? "none"); breakpoint \(breakpoint ?? "none"); tools \(tools); reasoning \(reasoning ?? "none"); text format \(textFormat); stream \(stream)"
        )
        for round in 1...3 {
            let moment = "It is now \(Date()). Answer in five words: what does the house keep?"
            var stableItem: [String: Any] = [
                "role": "developer",
                "content": [["type": "input_text", "text": stable]],
            ]
            for (field, value) in extra { stableItem[field] = value }
            var body: [String: Any] = [
                "model": model,
                "input": [
                    stableItem,
                    ["role": "user", "content": [["type": "input_text", "text": moment]]],
                ],
                "store": store,
                "max_output_tokens": 30,
            ]
            if let tier { body["service_tier"] = tier }
            if let key { body["prompt_cache_key"] = key }
            if let retention { body["prompt_cache_retention"] = retention }
            if let reasoning { body["reasoning"] = ["effort": reasoning] }
            if textFormat { body["text"] = ["format": ["type": "text"]] }
            if tools > 0 {
                body["tools"] = (0..<tools).map { index -> [String: Any] in
                    [
                        "type": "function", "name": "look_up_\(index)", "strict": false,
                        "description": "Looks up thing number \(index) in the world.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "subject_id": ["type": "string", "description": "An entity id."],
                                "limit": ["type": "integer", "description": "At most this many."],
                            ],
                            "required": [],
                        ],
                    ]
                }
            }
            if stream { body["stream"] = true }
            var request = URLRequest(url: URL(string: endpoint)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (raw, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Streamed: the usage is on the response.completed event, the last data: line.
            var data = raw
            if stream, status == 200 {
                let text = String(decoding: raw, as: UTF8.self)
                if let completed = text.split(separator: "\n").last(where: {
                    $0.hasPrefix("data: ") && $0.contains("response.completed")
                }) {
                    data = Data(completed.dropFirst(6).utf8)
                }
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("round \(round): HTTP \(status), unreadable body")
                continue
            }
            if status != 200 {
                print(
                    "round \(round): HTTP \(status): \(String(decoding: data.prefix(400), as: UTF8.self))"
                )
                continue
            }
            let usageObject = object["usage"] ?? (object["response"] as? [String: Any])?["usage"]
            let usage =
                usageObject.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .map { String(decoding: $0, as: UTF8.self) } ?? "no usage"
            print("round \(round): \(usage)")
            if round < 3 { try await Task.sleep(for: .seconds(pause)) }
        }
    }
}
