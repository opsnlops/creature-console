import Foundation
import Testing

@testable import creature_agent

@Suite("The Decisions API, for a name's kind (#239)")
struct DecisionsClientTests {
    private func response(_ json: String) throws -> DecisionsClient.Response {
        try JSONDecoder().decode(DecisionsClient.Response.self, from: Data(json.utf8))
    }

    @Test("The request is one choice: model, input, the question and its choices")
    func requestShape() throws {
        let request = DecisionsClient.Request(
            model: "gpt-6-luna", input: "Name: Rocket Taco",
            questions: [
                .init(
                    name: "kind", instructions: "What kind?",
                    choices: [
                        .init(value: "person", description: "A human being."),
                        .init(value: "place", description: nil),
                    ])
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(request), as: UTF8.self)
        #expect(
            json
                == #"{"input":"Name: Rocket Taco","model":"gpt-6-luna","questions":[{"choices":[{"description":"A human being.","value":"person"},{"value":"place"}],"instructions":"What kind?","name":"kind","type":"choice"}]}"#
        )
    }

    @Test(
        "The answer's bare choice, as the API gives it; a refusal or a value not offered is an error"
    )
    func answers() throws {
        let values = ["person", "place"]
        let bare = try response(
            #"{"model":"gpt-6-luna","answers":[{"type":"choice","name":"kind","choice":"place","probabilities":[{"value":"person","probability":0.0},{"value":"place","probability":0.94}],"confidence":0.94}],"usage":{"input_tokens":143,"output_tokens":0}}"#
        )
        #expect(
            try DecisionsClient.chosen(named: "kind", in: bare, among: values)
                == .init(value: "place", confidence: 0.94, inputTokens: 143))
        #expect(throws: DecisionsClient.Failure.refused) {
            try DecisionsClient.chosen(
                named: "kind", in: try response(#"{"answers":[{"type":"refusal","name":"kind"}]}"#),
                among: values)
        }
        #expect(throws: DecisionsClient.Failure.noAnswer) {
            try DecisionsClient.chosen(
                named: "kind",
                in: try response(#"{"answers":[{"type":"choice","name":"kind","choice":"tree"}]}"#),
                among: values)
        }
        #expect(throws: DecisionsClient.Failure.noAnswer) {
            try DecisionsClient.chosen(
                named: "kind", in: try response(#"{"answers":[]}"#), among: values)
        }
    }

    @Test("The judge sends the name and its context, capped - never a bird's prompt")
    func judgeInput() {
        let input = DecisionsKindJudge.input(name: "Rocket Taco", context: "lunch Saturday")
        #expect(input == "Name: Rocket Taco\n\nContext: lunch Saturday")
        let long = DecisionsKindJudge.input(
            name: "x", context: String(repeating: "a", count: 5_000))
        #expect(long.count < DecisionsKindJudge.maximumContext + 20)
        #expect(
            Set(DecisionsKindJudge.choices.map(\.value))
                == EntityNames.judgedKinds.union([DecisionsKindJudge.nobody]))
    }
}
