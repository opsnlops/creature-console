import Foundation
import Logging

struct OpenAIClient {

    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let logger: Logger
    private let traceResponses: Bool
    private let temperature: Double

    init(
        apiKey: String,
        model: String,
        systemPrompt: String,
        temperature: Double,
        logger: Logger,
        traceResponses: Bool
    ) {
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.logger = logger
        self.traceResponses = traceResponses
    }

    func respond(to prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIClientError.invalidURL
        }

        logger.debug("Sending OpenAI response request (model: \(model))")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ResponseRequest(
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            input: prompt
        )
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            logger.error("OpenAI request failed with status \(httpResponse.statusCode)")
            throw OpenAIClientError.httpError(code: httpResponse.statusCode, body: message)
        }

        if traceResponses, let bodyString = String(data: data, encoding: .utf8) {
            logger.info("OpenAI raw response: \(bodyString)")
        }

        let output = try OpenAIResponseParser.outputText(from: data)
        logger.debug("OpenAI response received (chars: \(output.count))")
        return output
    }
}

private struct ResponseRequest: Encodable {
    let model: String
    let instructions: String
    let temperature: Double
    let input: String

    init(model: String, systemPrompt: String, temperature: Double, input: String) {
        self.model = model
        self.instructions = systemPrompt
        self.temperature = temperature
        self.input = input
    }
}

enum OpenAIClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(code: Int, body: String)
    case missingOutputText

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OpenAI URL"
        case .invalidResponse:
            return "Invalid OpenAI response"
        case .httpError(let code, let body):
            if body.isEmpty {
                return "OpenAI API returned status \(code)"
            }
            return "OpenAI API returned status \(code): \(body)"
        case .missingOutputText:
            return "OpenAI response did not include output text"
        }
    }
}
