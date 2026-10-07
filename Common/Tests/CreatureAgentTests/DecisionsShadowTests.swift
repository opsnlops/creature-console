import Foundation
import InMemoryTracing
import Testing
import Tracing

@testable import creature_agent

@Suite("The Decisions API, in shadow (#221)")
struct DecisionsShadowTests {
    @Test("The request is the guide's shape: model, input, one predicate with instructions")
    func requestShape() throws {
        let request = DecisionsClient.Request(
            model: "gpt-6-luna", input: "the scene",
            questions: [.init(name: "speaks", instructions: "Would Kenny speak?")])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(request), as: UTF8.self)
        #expect(
            json
                == #"{"input":"the scene","model":"gpt-6-luna","questions":[{"instructions":"Would Kenny speak?","name":"speaks","type":"predicate"}]}"#
        )
    }

    @Test("Answers: the predicate's probability; a refusal or a missing answer is an error")
    func answers() throws {
        func response(_ json: String) throws -> DecisionsClient.Response {
            try JSONDecoder().decode(DecisionsClient.Response.self, from: Data(json.utf8))
        }
        // The guide's predicate answer, as given.
        let yes = try response(
            #"{"answers":[{"type":"predicate","name":"speaks","probability":0.92}]}"#)
        #expect(try DecisionsClient.probability(named: "speaks", in: yes) == 0.92)
        #expect(yes.usage == nil)
        let refused = try response(#"{"answers":[{"type":"refusal","name":"speaks"}]}"#)
        #expect(throws: DecisionsClient.Failure.refused) {
            try DecisionsClient.probability(named: "speaks", in: refused)
        }
        #expect(throws: DecisionsClient.Failure.noAnswer) {
            try DecisionsClient.probability(named: "speaks", in: try response(#"{"answers":[]}"#))
        }
        let counted = try response(
            #"{"answers":[{"type":"predicate","name":"speaks","probability":0.1}],"usage":{"input_tokens":812}}"#
        )
        #expect(counted.usage?.inputTokens == 812)
    }

    @Test("The bird's own view, role by role, and a question about that bird")
    func inputAndInstructions() {
        let input = DecisionsShadow.input(from: [
            .init(role: .system, content: "You are Kenny."),
            .init(role: .user, content: "(A person was just seen at the carport.)"),
        ])
        #expect(
            input == "[system]\nYou are Kenny.\n\n[user]\n(A person was just seen at the carport.)")
        #expect(DecisionsShadow.instructions(for: "Kenny").contains("Would Kenny speak now"))
    }

    @Test("Recorded on the turn's span: the probability, or why there is none - never in the way")
    func recordsOnTheSpan() async {
        let tracer = InMemoryTracer()
        let shadow = DecisionsShadow(
            client: DecisionsClient(apiKey: "test", model: "gpt-6-luna"), grace: .milliseconds(100))

        let answered = tracer.startSpan("agent.scene_turn")
        await shadow.record(Task { (0.25, 900, Duration.milliseconds(180)) }, on: answered)
        #expect(answered.attributes.get("decisions.speak_probability") == .double(0.25))
        #expect(answered.attributes.get("decisions.input_tokens") == .int64(900))
        #expect(answered.attributes.get("decisions.duration_ms") == .double(180))

        let failed = tracer.startSpan("agent.scene_turn")
        await shadow.record(
            Task { throw DecisionsClient.Failure.http(429, "slow down") }, on: failed)
        #expect(failed.attributes.get("decisions.error") == .string("HTTP 429: slow down"))
        #expect(failed.attributes.get("decisions.speak_probability") == nil)

        // A slow answer is cut off at the grace, so a turn is never held up.
        let slow = tracer.startSpan("agent.scene_turn")
        let started = ContinuousClock.now
        await shadow.record(
            Task {
                try await Task.sleep(for: .seconds(5))
                return (0.9, nil, Duration.seconds(5))
            }, on: slow)
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(slow.attributes.get("decisions.error") == .string("timed out"))
    }
}
