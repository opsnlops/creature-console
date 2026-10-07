import Foundation
import Logging
import Tracing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// OpenAI's Decisions API (`POST /v1/decisions`, public beta from 2026-10-07): typed answers -
/// here one `predicate`, "would this bird speak?" - about ten times faster than the Responses
/// API, at $0.10 per million input tokens and nothing for output. Asked in shadow beside every
/// scene turn and recorded on the turn's span; it changes nothing the bird does (#221,
/// docs/decisions-shadow-plan.md).
struct DecisionsClient: Sendable {
    static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    struct Request: Encodable, Equatable {
        struct Question: Encodable, Equatable {
            let type = "predicate"
            let name: String
            let instructions: String
        }
        let model: String
        let input: String
        let questions: [Question]
    }

    /// The answers; only what this shadow reads. A `refusal` carries no probability.
    struct Response: Decodable, Equatable {
        struct Answer: Decodable, Equatable {
            let type: String
            let name: String
            let probability: Double?
        }
        struct Usage: Decodable, Equatable {
            let inputTokens: Int?
            enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens" }
        }
        let answers: [Answer]
        let usage: Usage?
    }

    enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int, String)
        case refused
        case noAnswer

        var description: String {
            switch self {
            case .http(let code, let body): "HTTP \(code): \(body)"
            case .refused: "refused"
            case .noAnswer: "no answer"
            }
        }
    }

    let apiKey: String
    let model: String
    var baseURL: URL = DecisionsClient.defaultBaseURL
    var timeout: TimeInterval = 10

    /// The probability the predicate is true, and the input tokens it cost.
    func predicate(name: String, instructions: String, input: String) async throws -> (
        probability: Double, inputTokens: Int?
    ) {
        let body = Request(
            model: model, input: input,
            questions: [Request.Question(name: name, instructions: instructions)])
        var request = URLRequest(url: baseURL.appending(path: "decisions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
            throw Failure.http(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (try Self.probability(named: name, in: decoded), decoded.usage?.inputTokens)
    }

    /// The named predicate's probability; a refusal or a missing answer is an error.
    static func probability(named name: String, in response: Response) throws -> Double {
        guard let answer = response.answers.first(where: { $0.name == name }) else {
            throw Failure.noAnswer
        }
        if answer.type == "refusal" { throw Failure.refused }
        guard let probability = answer.probability else { throw Failure.noAnswer }
        return probability
    }
}

/// The shadow: ask, beside a scene turn, whether the bird would speak; write the answer on the
/// turn's span. It never delays a turn by more than `grace` after the bird has decided, and
/// never fails one - every problem is an attribute, not an error.
struct DecisionsShadow: Sendable {
    let client: DecisionsClient
    /// How long, after the bird has decided, the shadow may still finish.
    var grace: Duration = .seconds(3)

    static let predicateName = "speaks"

    /// What the predicate asks about `bird`, given its own view of the scene.
    static func instructions(for bird: String) -> String {
        """
        The text is everything \(bird) is shown on this turn of the scene: who \(bird) is, what \
        the world knows, and the scene so far. Would \(bird) speak now - say something new in \
        \(bird)'s own voice that adds to the scene - rather than stay quiet? \(bird) stays quiet \
        when there is nothing to add, when another bird has already said it, or when the \
        moment does not call for \(bird).
        """
    }

    /// The bird's prompt as one text: each message, its role first.
    static func input(from messages: [LocalLLMClient.Message]) -> String {
        messages.map { "[\($0.role)]\n\($0.content)" }.joined(separator: "\n\n")
    }

    /// Starts the question now; `record` later puts the answer on the span.
    func start(bird: String, messages: [LocalLLMClient.Message]) -> Task<
        (probability: Double, inputTokens: Int?, duration: Duration), any Error
    > {
        let client = client
        let input = Self.input(from: messages)
        let instructions = Self.instructions(for: bird)
        return Task {
            let clock = ContinuousClock()
            let started = clock.now
            let answer = try await client.predicate(
                name: Self.predicateName, instructions: instructions, input: input)
            return (answer.probability, answer.inputTokens, clock.now - started)
        }
    }

    /// Waits up to `grace` for the answer, then writes it - or why there is none - on `span`.
    func record(
        _ question: Task<(probability: Double, inputTokens: Int?, duration: Duration), any Error>,
        on span: any Span
    ) async {
        let grace = grace
        let outcome = await withTaskGroup(
            of: Result<(probability: Double, inputTokens: Int?, duration: Duration), any Error>?
                .self
        ) { group in
            group.addTask { await question.result }
            group.addTask {
                try? await Task.sleep(for: grace)
                // The question itself is cancelled, not just this group: a group waits for all
                // its children, and the one awaiting the answer cannot be interrupted - a slow
                // answer would hold the turn for as long as it took.
                question.cancel()
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        switch outcome {
        case .success(let answer)?:
            span.attributes["decisions.speak_probability"] = answer.probability
            span.attributes["decisions.duration_ms"] =
                Double(answer.duration.components.seconds) * 1_000
                + Double(answer.duration.components.attoseconds) / 1e15
            if let tokens = answer.inputTokens {
                span.attributes["decisions.input_tokens"] = tokens
            }
        case .failure(let error)?:
            span.attributes["decisions.error"] = "\(error)"
        case nil:
            question.cancel()
            span.attributes["decisions.error"] = "timed out"
        }
    }
}
