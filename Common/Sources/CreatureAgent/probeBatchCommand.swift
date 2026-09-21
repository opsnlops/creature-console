import ArgumentParser
import Foundation
import Logging

/// `creature-agent probe-batch`: one tiny request through the Batch API, end to end - the
/// file upload, the batch, the wait, the output file, the usage - so the nightly memory's
/// road is proven in minutes with a day key, not discovered at 3:30 AM.
struct ProbeBatch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-batch",
        abstract: "Send one request through the Batch API and print what came back")

    @Option(help: "The model, e.g. gpt-6-astra") var model: String
    @Option(help: "Minutes to wait for the batch before cancelling it") var waitMinutes = 30
    @Option(help: "Seconds between looks") var every = 20
    @Option(
        help:
            "reasoning.effort, as the memory client sends it; \"none\" sends a temperature instead, which a reasoning model refuses"
    )
    var reasoning = "medium"

    func run() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty
        else {
            throw ValidationError("OPENAI_API_KEY is not set")
        }
        let logger = Logger(label: "probe-batch")
        let client = OpenAIClient(
            apiKey: apiKey, model: model, systemPrompt: "unused", temperature: 0.7,
            reasoningEffort: reasoning == "none" ? nil : reasoning, logger: logger,
            traceResponses: false)
        let batches = OpenAIBatchClient(apiKey: apiKey, logger: logger)
        let customID = "probe:\(UUID().uuidString.lowercased())"
        let transcript = [
            LocalLLMClient.Message(
                role: .system,
                content: "Answer with one JSON object and nothing else: {\"words\": \"...\"}."),
            LocalLLMClient.Message(
                role: .user, content: "What does a purple house keep? Five words."),
        ]
        let started = Date()
        let batchID = try await batches.submit(
            lines: [try client.batchLine(for: transcript, customID: customID)],
            metadata: ["creature": "probe"])
        print("batch \(batchID) submitted; waiting up to \(waitMinutes) minutes")
        let output = try await batches.output(
            of: batchID, every: .seconds(every),
            deadline: started.addingTimeInterval(Double(waitMinutes) * 60))
        let answer = try client.jsonAnswer(
            fromBatch: try OpenAIBatchClient.result(for: customID, in: output), batchID: batchID)
        print(
            "answer after \(Int(Date().timeIntervalSince(started))) s: \(String(decoding: answer, as: UTF8.self))"
        )
    }
}
