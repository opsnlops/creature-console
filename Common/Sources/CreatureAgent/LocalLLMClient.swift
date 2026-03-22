import Foundation
import Logging

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct LocalLLMClient {

    private let host: String
    private let port: Int
    private let model: String
    private let systemPrompt: String
    private let temperature: Double
    private let maxTokens: Int
    private let minSentenceChars: Int
    private let logger: Logger
    private let traceResponses: Bool
    private let history: ConversationHistory

    init(
        host: String,
        port: Int,
        model: String,
        systemPrompt: String,
        temperature: Double,
        maxTokens: Int,
        minSentenceChars: Int = 0,
        conversationHistorySize: Int,
        logger: Logger,
        traceResponses: Bool
    ) {
        self.host = host
        self.port = port
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.minSentenceChars = minSentenceChars
        self.logger = logger
        self.traceResponses = traceResponses
        self.history = ConversationHistory(maxExchanges: conversationHistorySize)
    }

    /// Non-streaming response — waits for the full LLM output.
    /// Used when streaming isn't needed or as a fallback.
    func respond(to prompt: String) async throws -> String {
        var fullText = ""
        for await sentence in respondStreaming(to: prompt) {
            fullText += sentence
        }

        let output = LocalLLMClient.stripThinkTags(fullText)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if output.isEmpty {
            throw LocalLLMClientError.missingOutputText
        }

        return output
    }

    /// Stream LLM response sentence-by-sentence.
    ///
    /// Connects to llama-server with `stream: true`, parses SSE events,
    /// accumulates tokens, and yields each complete sentence as soon as
    /// a sentence-ending punctuation mark (. ! ?) is followed by a space
    /// or end-of-stream.
    ///
    /// The full response is also appended to conversation history when
    /// the stream completes.
    func respondStreaming(to prompt: String) -> AsyncStream<String> {
        let host = self.host
        let port = self.port
        let model = self.model
        let systemPrompt = self.systemPrompt
        let temperature = self.temperature
        let maxTokens = self.maxTokens
        let logger = self.logger
        let traceResponses = self.traceResponses
        let history = self.history

        return AsyncStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "http://\(host):\(port)/v1/chat/completions")
                    else {
                        logger.error("Invalid local LLM URL")
                        continuation.finish()
                        return
                    }

                    var messages: [[String: String]] = [
                        ["role": "system", "content": systemPrompt]
                    ]

                    let historyMessages = await history.allMessages()
                    for msg in historyMessages {
                        messages.append(["role": msg.role, "content": msg.content])
                    }

                    messages.append(["role": "user", "content": prompt])

                    let body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "temperature": temperature,
                        "max_tokens": maxTokens,
                        "stop": ["\n\n\n", "\n\n"],
                        "stream": true,
                    ]

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    logger.debug("Starting streaming LLM request (model: \(model))")

                    // Use a delegate-based approach for SSE streaming that works
                    // on both macOS and Linux (URLSession.bytes is not available
                    // in FoundationNetworking on Linux)
                    let sseDelegate = SSEDataDelegate()
                    let session = URLSession(
                        configuration: .default, delegate: sseDelegate, delegateQueue: nil)
                    let task = session.dataTask(with: request)
                    task.resume()

                    // Parse SSE stream from the delegate's async line sequence
                    var sentenceBuffer = ""
                    var fullResponse = ""
                    var insideThinkTag = false
                    var sentenceCount = 0

                    for await line in sseDelegate.lines {
                        // SSE format: lines starting with "data: "
                        guard line.hasPrefix("data: ") else {
                            continue
                        }

                        let jsonStr = String(line.dropFirst(6))

                        // End of stream
                        if jsonStr == "[DONE]" {
                            break
                        }

                        // Parse the delta content from the SSE chunk
                        guard let jsonData = jsonStr.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: jsonData)
                                as? [String: Any],
                            let choices = json["choices"] as? [[String: Any]],
                            let firstChoice = choices.first,
                            let delta = firstChoice["delta"] as? [String: Any],
                            let content = delta["content"] as? String
                        else {
                            continue
                        }

                        // Handle <think> tags — skip content inside them
                        for char in content {
                            if insideThinkTag {
                                // Look for closing </think>
                                sentenceBuffer.append(char)
                                if sentenceBuffer.hasSuffix("</think>") {
                                    // Remove the entire think block from the buffer
                                    if let range = sentenceBuffer.range(of: "<think>") {
                                        sentenceBuffer = String(sentenceBuffer[..<range.lowerBound])
                                    } else {
                                        sentenceBuffer = ""
                                    }
                                    insideThinkTag = false
                                }
                                continue
                            }

                            sentenceBuffer.append(char)

                            // Detect <think> tag start
                            if sentenceBuffer.hasSuffix("<think>") {
                                insideThinkTag = true
                                continue
                            }

                            // Check for sentence boundary
                            if let splitIdx = sentenceBoundaryIndex(sentenceBuffer) {
                                let sentence = String(sentenceBuffer[...splitIdx])
                                    .trimmingCharacters(in: .whitespaces)
                                let remainder = String(
                                    sentenceBuffer[sentenceBuffer.index(after: splitIdx)...])
                                // Strip wrapping quotes that LLMs sometimes add
                                let cleanSentence =
                                    sentence
                                    .trimmingCharacters(
                                        in: CharacterSet(
                                            charactersIn: "\"'\u{201C}\u{201D}")
                                    )
                                    .trimmingCharacters(in: .whitespaces)
                                if !cleanSentence.isEmpty {
                                    if cleanSentence.count >= minSentenceChars {
                                        // Sentence meets minimum length — yield it
                                        sentenceCount += 1
                                        fullResponse += cleanSentence + " "
                                        logger.info(
                                            "LLM sentence \(sentenceCount): \"\(cleanSentence)\" (\(cleanSentence.count) chars)"
                                        )
                                        continuation.yield(cleanSentence)
                                        sentenceBuffer = remainder
                                    } else {
                                        // Too short for TTS — keep in buffer, merge with next sentence
                                        logger.debug(
                                            "LLM sentence too short (\(cleanSentence.count) < \(minSentenceChars) chars), buffering: \"\(cleanSentence)\""
                                        )
                                        // Don't clear the buffer — the split point stays and
                                        // more text will accumulate until we hit the minimum
                                    }
                                } else {
                                    sentenceBuffer = remainder
                                }
                            }
                        }
                    }

                    // Yield any remaining text that didn't end with sentence punctuation
                    // Filter out fragments that are just quotes or punctuation (LLM wrapping artifacts)
                    let remaining =
                        sentenceBuffer
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}"))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remaining.isEmpty {
                        sentenceCount += 1
                        fullResponse += remaining
                        logger.info(
                            "LLM sentence \(sentenceCount) (final): \"\(remaining)\" (\(remaining.count) chars)"
                        )
                        continuation.yield(remaining)
                    }

                    if traceResponses {
                        logger.info("LLM full streaming response: \(fullResponse)")
                    }

                    logger.debug(
                        "LLM streaming complete: \(sentenceCount) sentences, \(fullResponse.count) chars"
                    )

                    // Save to conversation history
                    let cleanOutput = LocalLLMClient.stripThinkTags(fullResponse)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanOutput.isEmpty {
                        await history.append(
                            userMessage: prompt, assistantMessage: cleanOutput)
                    }

                    continuation.finish()

                } catch {
                    logger.error("LLM streaming error: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    /// Find a sentence boundary in the buffer.
    /// Returns the index of the sentence-ending punctuation mark (. ! ?) if
    /// the next character indicates a new sentence is starting (space, uppercase
    /// letter, or opening quote). Returns nil if no boundary is found.
    ///
    /// Handles both standard ("Hello. World") and no-space ("Hello!World")
    /// patterns common in LLM output.
    private func sentenceBoundaryIndex(_ buffer: String) -> String.Index? {
        guard buffer.count >= 2 else { return nil }

        let lastIdx = buffer.index(before: buffer.endIndex)
        let lastChar = buffer[lastIdx]
        let penultIdx = buffer.index(before: lastIdx)
        let penultChar = buffer[penultIdx]

        let isPunct = { (c: Character) -> Bool in
            c == "." || c == "!" || c == "?"
        }

        let isNewSentenceStart = { (c: Character) -> Bool in
            c == " " || c.isUppercase || c == "\"" || c == "\u{201C}"
        }

        // "X " or "XA" where X is punctuation
        if isPunct(penultChar) && isNewSentenceStart(lastChar) {
            return penultIdx
        }

        // Check for closing quote: X"A or X" A
        if buffer.count >= 3 {
            let threeBackIdx = buffer.index(penultIdx, offsetBy: -1)
            let threeBack = buffer[threeBackIdx]

            if isPunct(threeBack) && (penultChar == "\"" || penultChar == "'")
                && isNewSentenceStart(lastChar)
            {
                // Split after the closing quote
                return penultIdx
            }
        }

        return nil
    }

    internal static func stripThinkTags(_ text: String) -> String {
        let pattern = "<think>[\\s\\S]*?</think>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

/// URLSession delegate that collects SSE data and exposes it as an AsyncStream of lines.
/// Works on both macOS and Linux (FoundationNetworking).
private final class SSEDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var lineContinuation: AsyncStream<String>.Continuation?
    private var buffer = ""

    let lines: AsyncStream<String>

    override init() {
        var cont: AsyncStream<String>.Continuation?
        self.lines = AsyncStream { cont = $0 }
        super.init()
        self.lineContinuation = cont
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        // Split on newlines and yield complete lines
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            buffer = String(buffer[newlineRange.upperBound...])
            if !line.isEmpty {
                lineContinuation?.yield(line)
            }
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        // Flush any remaining data in the buffer
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            lineContinuation?.yield(remaining)
        }
        lineContinuation?.finish()
    }
}

enum LocalLLMClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(code: Int, body: String)
    case missingOutputText

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid local LLM URL"
        case .invalidResponse:
            return "Invalid local LLM response"
        case .httpError(let code, let body):
            if body.isEmpty {
                return "Local LLM API returned status \(code)"
            }
            return "Local LLM API returned status \(code): \(body)"
        case .missingOutputText:
            return "Local LLM response did not include output text"
        }
    }
}
