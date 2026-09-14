import Foundation

struct OpenAIResponseParser {
    /// The text a Responses API SSE line carries, or `nil` for anything that is not an
    /// `output_text.delta` event (lifecycle events, blank lines, `[DONE]`).
    static func streamedDelta(from line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        return streamedDelta(fromData: String(line.dropFirst(6)))
    }

    /// The same, for a frame's `data` payload once the SSE framing has been removed.
    static func streamedDelta(fromData json: String) -> String? {
        guard json != "[DONE]", let data = json.data(using: .utf8),
            let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
            event.type == "response.output_text.delta"
        else { return nil }
        return event.delta
    }

    static func outputText(from data: Data) throws -> String {
        let decoder = JSONDecoder()
        let response = try decoder.decode(ResponseEnvelope.self, from: data)
        if let output = response.outputTextValue {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw OpenAIClientError.missingOutputText
    }
}

private struct ResponseEnvelope: Decodable {
    let output: [ResponseOutputItem]?

    var outputTextValue: String? {
        return output?.compactMap { $0.textValue }.first
    }
}

private struct ResponseOutputItem: Decodable {
    let content: [ResponseContent]?
    let type: String?

    var textValue: String? {
        switch type {
        case "message":
            return content?.first(where: { $0.type == "output_text" })?.text
        case "output_text":
            return content?.compactMap { $0.text }.first
        default:
            return nil
        }
    }
}

private struct ResponseContent: Decodable {
    let text: String?
    let type: String?
}

private struct StreamEvent: Decodable {
    let type: String
    let delta: String?
}
