import Common
import Foundation
import Logging
import Tracing

enum PhysicalSpeechStageError: Error, Equatable {
    /// Creature Server would not open a streaming speech session.
    case sessionStartFailed(String)
    /// The session opened and sentences were sent, but the performance could not be finished.
    case sessionFinishFailed(String)

    var code: String {
        switch self {
        case .sessionStartFailed: "physical_speech_start_failed"
        case .sessionFinishFailed: "physical_speech_finish_failed"
        }
    }
}

/// The room: something that can speak Beaky's sentences through her body as they arrive.
///
/// The session is opened lazily on the first sentence, so a mind that ends up saying nothing
/// leaves no empty performance behind. Returns the provider's reference for the performance
/// (Creature Server's animation ID), or `nil` when no sentence was ever offered.
protocol PhysicalSpeechStaging: Sendable {
    func perform(_ sentences: AsyncStream<String>) async throws -> String?
}

/// Creature Server's streaming ad-hoc speech session — the same path the MQTT agent uses, so
/// Beaky starts talking about two seconds after her first sentence exists.
struct CreatureServerSpeechStage: PhysicalSpeechStaging {
    private let server: CreatureServerClient
    private let creatureID: CreatureIdentifier
    private let logger: Logger

    init(server: CreatureServerClient, creatureID: CreatureIdentifier, logger: Logger) {
        self.server = server
        self.creatureID = creatureID
        self.logger = logger
    }

    func perform(_ sentences: AsyncStream<String>) async throws -> String? {
        try await withSpan("creature.server.perform", ofKind: .client) { span in
            span.attributes["creature.id"] = creatureID
            var sessionID: String?
            var sentenceCount = 0
            for await sentence in sentences {
                if sessionID == nil {
                    switch await server.startStreamingAdHocSpeech(
                        creatureId: creatureID, resumePlaylist: true)
                    {
                    case .success(let started):
                        sessionID = started.sessionId
                        span.attributes["streaming.session_id"] = started.sessionId
                    case .failure(let error):
                        let message = ServerError.detailedMessage(from: error)
                        span.recordError(error)
                        throw PhysicalSpeechStageError.sessionStartFailed(message)
                    }
                }
                guard let sessionID else { continue }
                sentenceCount += 1
                if case .failure(let error) = await server.addStreamingAdHocText(
                    sessionId: sessionID, text: sentence)
                {
                    // One lost sentence is a stumble, not a failed performance; the rest of the
                    // turn still plays and history records what was offered.
                    logger.error(
                        "Creature Server dropped a sentence",
                        metadata: [
                            "streaming.session_id": "\(sessionID)",
                            "error": "\(ServerError.detailedMessage(from: error))",
                        ]
                    )
                }
            }
            guard let sessionID else { return nil }
            span.attributes["speech.sentences"] = sentenceCount
            switch await server.finishStreamingAdHocSpeech(sessionId: sessionID) {
            case .success(let finished):
                span.attributes["speech.animation_id"] = finished.animationId ?? "unknown"
                return finished.animationId
            case .failure(let error):
                span.recordError(error)
                throw PhysicalSpeechStageError.sessionFinishFailed(
                    ServerError.detailedMessage(from: error))
            }
        }
    }
}
