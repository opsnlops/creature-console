import Foundation
import WorldCore

/// What a bird learns in a whisper is that bird's alone, and the World decides it at the door
/// (#263). A mind's `facts.given` is caused by the percept it answered. When that percept is an
/// utterance April whispered to a bird ("@beaky …", marked at ingest, #261), the fact is marked
/// with that bird, and no other bird is handed it. On 2026-10-22 Beaky kept six facts while
/// April whispered with her; the next remembering of the day handed two of them to Mango and
/// Kenny as things "the house recorded". A mark the mind sent itself is never taken on its
/// word: the World's is the only one.
struct WhisperDesk: Sendable {
    /// One event by id: the percept a keeping answered.
    let event: @Sendable (EventID) async throws -> WorldEventEnvelope?
    /// The bird an utterance was whispered to, from its ingress.
    let whisperedTo: @Sendable (UtteranceID) async throws -> EntityID?

    func mark(_ event: WorldEventEnvelope) async throws -> WorldEventEnvelope {
        guard event.type == GivenFactAnnouncement.eventType, event.source.kind == "mind" else {
            return event
        }
        var marked = event
        marked.payload[GivenFactAnnouncement.aloneWithKey] = nil
        if let bird = try await whisper(answeredBy: event) {
            marked.payload[GivenFactAnnouncement.aloneWithKey] = .string(bird.rawValue)
        }
        return marked
    }

    /// The bird of the whisper `keeping` answered, if it answered one.
    private func whisper(answeredBy keeping: WorldEventEnvelope) async throws -> EntityID? {
        for case .event(let id) in keeping.causedBy {
            guard let cause = try await event(id), cause.type == PersonUtterancePercept.eventType,
                case .object(let utterance)? = cause.payload["utterance"],
                case .string(let raw)? = utterance["utterance_id"],
                let utteranceID = UtteranceID(rawValue: raw)
            else { continue }
            if let bird = try await whisperedTo(utteranceID) { return bird }
        }
        return nil
    }
}
