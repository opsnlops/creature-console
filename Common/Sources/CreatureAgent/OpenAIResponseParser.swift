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

    /// A tool the model asks the mind to run, with the id its answer must carry back.
    struct FunctionCall: Sendable, Equatable {
        var callID: String
        var name: String
        var arguments: String
    }

    /// A completed function call in the stream: `response.output_item.done` with a
    /// `function_call` item (the arguments whole). Nothing for any other event.
    static func streamedFunctionCall(fromData json: String) -> FunctionCall? {
        guard json != "[DONE]", let data = json.data(using: .utf8),
            let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
            event.type == "response.output_item.done", let item = event.item
        else { return nil }
        return item.functionCall
    }

    /// The function calls a whole (non-streamed) response asks for, in order.
    static func functionCalls(from data: Data) -> [FunctionCall] {
        guard let response = try? JSONDecoder().decode(ResponseEnvelope.self, from: data) else {
            return []
        }
        return response.output?.compactMap(\.functionCall) ?? []
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
    let callID: String?
    let name: String?
    let arguments: String?

    private enum CodingKeys: String, CodingKey {
        case content, type, name, arguments
        case callID = "call_id"
    }

    var functionCall: OpenAIResponseParser.FunctionCall? {
        guard type == "function_call", let name, let callID else { return nil }
        return OpenAIResponseParser.FunctionCall(
            callID: callID, name: name, arguments: arguments ?? "{}")
    }

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
    let item: ResponseOutputItem?
}
