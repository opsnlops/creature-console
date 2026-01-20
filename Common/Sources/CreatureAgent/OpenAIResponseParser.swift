import Foundation

struct OpenAIResponseParser {
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
