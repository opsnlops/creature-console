import Foundation
import Testing

@testable import creature_agent

@Suite("LMStudioResponseParser")
struct LMStudioResponseParserTests {
    @Test("Parses valid chat completion response")
    func validResponse() throws {
        let json = """
            {
                "choices": [
                    {
                        "message": {
                            "content": "Hello from LM Studio!"
                        }
                    }
                ]
            }
            """
        let data = Data(json.utf8)
        let result = try LMStudioResponseParser.outputText(from: data)
        #expect(result == "Hello from LM Studio!")
    }

    @Test("Throws on empty choices array")
    func emptyChoices() {
        let json = """
            { "choices": [] }
            """
        let data = Data(json.utf8)
        #expect(throws: LMStudioClientError.self) {
            try LMStudioResponseParser.outputText(from: data)
        }
    }

    @Test("Throws on missing content")
    func missingContent() {
        let json = """
            {
                "choices": [
                    {
                        "message": {
                            "content": null
                        }
                    }
                ]
            }
            """
        let data = Data(json.utf8)
        #expect(throws: LMStudioClientError.self) {
            try LMStudioResponseParser.outputText(from: data)
        }
    }

    @Test("Trims whitespace from content")
    func trimsWhitespace() throws {
        let json = """
            {
                "choices": [
                    {
                        "message": {
                            "content": "  trimmed  \\n"
                        }
                    }
                ]
            }
            """
        let data = Data(json.utf8)
        let result = try LMStudioResponseParser.outputText(from: data)
        #expect(result == "trimmed")
    }
}
