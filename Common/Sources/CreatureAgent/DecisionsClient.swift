import Foundation
import Tracing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// OpenAI's Decisions API (`POST /v1/decisions`, public beta from 2026-10-07): typed answers
/// about ten times faster than the Responses API, at $0.10 per million input tokens and nothing
/// for output. Here, one `choice` at a time: a judgement that needs a model but not a bird's
/// whole prompt - what kind of thing a name is (#239, docs/entity-kinds-plan.md).
struct DecisionsClient: Sendable {
    static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    struct Choice: Encodable, Equatable, Sendable {
        let value: String
        let description: String?
    }

    struct Request: Encodable, Equatable {
        struct Question: Encodable, Equatable {
            let type = "choice"
            let name: String
            let instructions: String
            let choices: [Choice]
        }
        let model: String
        let input: String
        let questions: [Question]
    }

    /// The answers; only what is read here. A `refusal` carries no choice.
    struct Response: Decodable, Equatable {
        struct Answer: Decodable, Equatable {
            let type: String
            let name: String
            /// The chosen value, bare: `"choice": "place"` (seen live 2026-10-16).
            let choice: String?
            let confidence: Double?
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

    struct Chosen: Equatable, Sendable {
        let value: String
        let confidence: Double?
        let inputTokens: Int?
    }

    let apiKey: String
    let model: String
    var baseURL: URL = DecisionsClient.defaultBaseURL
    var timeout: TimeInterval = 10

    /// Which of `choices` the input is, by `instructions`.
    func choice(name: String, instructions: String, choices: [Choice], input: String)
        async throws -> Chosen
    {
        let body = Request(
            model: model, input: input,
            questions: [.init(name: name, instructions: instructions, choices: choices)])
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
        return try Self.chosen(
            named: name, in: try JSONDecoder().decode(Response.self, from: data),
            among: choices.map(\.value))
    }

    /// The named answer's value, which must be one of `values`; a refusal or anything else is
    /// an error.
    static func chosen(named name: String, in response: Response, among values: [String])
        throws -> Chosen
    {
        guard let answer = response.answers.first(where: { $0.name == name }) else {
            throw Failure.noAnswer
        }
        if answer.type == "refusal" { throw Failure.refused }
        guard let value = answer.choice, values.contains(value) else { throw Failure.noAnswer }
        return Chosen(
            value: value, confidence: answer.confidence, inputTokens: response.usage?.inputTokens)
    }
}

/// What kind of entity a name the world does not hold is - asked when a mind wrote a bare name
/// instead of `kind: name`. Nil is "nobody": a group, or nothing a fact belongs on.
protocol EntityKindJudging: Sendable {
    func kind(of name: String, in context: String) async throws -> String?
}

/// The judgement as one Decisions `choice`: the name and the line it came from, never the
/// bird's prompt (April: "We don't need to send the full 10k prompt for classification
/// things").
struct DecisionsKindJudge: EntityKindJudging {
    let client: DecisionsClient

    static let questionName = "kind"
    static let nobody = "nobody"
    /// The most of the line and its conversation sent: enough to tell a taco shop from a
    /// person, a few hundred tokens.
    static let maximumContext = 2_400

    /// Tried live on fifteen made-up names (2026-10-16): without the venue and event lines,
    /// "Rocket Taco" and a church came back as things; with them, fourteen of fifteen were
    /// right, the miss a bare "the Bridge" that the world's own id catches first.
    static let choices: [DecisionsClient.Choice] = [
        .init(
            value: "person",
            description: "A human being, named or by role (\"Tamara\", \"the mail carrier\")."),
        .init(
            value: "place",
            description: "Somewhere one goes or is: a restaurant, cafe, shop, bar, church, "
                + "school, park, town, room, door, yard."),
        .init(
            value: "thing",
            description: "An object, device, computer, vehicle, app, or project; or an event or "
                + "occasion (\"the potluck\", \"Tuesday's appointment\")."),
        .init(
            value: "spell",
            description: "One of April's spells: something she built that lets the birds notice "
                + "or do something."),
        .init(
            value: nobody,
            description: "More than one entity (\"Kenny and Mango\"), or nothing a fact could be "
                + "kept about."),
    ]

    static let instructions = """
        A bird in April's house wrote the name below in a note; the note and the conversation \
        around it are given for context. \
        Decide what the name refers to. A business or venue people go to - a restaurant, cafe, \
        shop, bar, church, school, park - is a place, even though it is also an organization. \
        An event or occasion is a thing, even when it happens at a place.
        """

    static func input(name: String, context: String) -> String {
        "Name: \(name)\n\nContext: \(context.prefix(maximumContext))"
    }

    func kind(of name: String, in context: String) async throws -> String? {
        try await withSpan("agent.entity_kind") { span in
            span.attributes["agent.entity_kind.name"] = name
            span.attributes["decisions.model"] = client.model
            let clock = ContinuousClock()
            let started = clock.now
            do {
                let chosen = try await client.choice(
                    name: Self.questionName, instructions: Self.instructions,
                    choices: Self.choices, input: Self.input(name: name, context: context))
                let took = clock.now - started
                span.attributes["decisions.choice"] = chosen.value
                span.attributes["decisions.duration_ms"] =
                    Double(took.components.seconds) * 1_000
                    + Double(took.components.attoseconds) / 1e15
                if let confidence = chosen.confidence {
                    span.attributes["decisions.confidence"] = confidence
                }
                if let tokens = chosen.inputTokens {
                    span.attributes["decisions.input_tokens"] = tokens
                }
                return chosen.value == Self.nobody ? nil : chosen.value
            } catch {
                span.attributes["decisions.error"] = "\(error)"
                throw error
            }
        }
    }
}
