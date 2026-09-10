import Foundation
import SwiftData
import WorldCore

/// SwiftData outbox entry for a person utterance awaiting canonical server acceptance.
@Model
final class PendingUtteranceModel {
    @Attribute(.unique) var id: String
    var conversationID: String
    var occurredAt: Date
    var inReplyToItemID: String?
    var payload: Data

    init(utterance: PersonUtterance, inReplyToItemID: ConversationItemID?) throws {
        id = utterance.utteranceID.rawValue
        conversationID = utterance.conversationID.rawValue
        occurredAt = utterance.occurredAt
        self.inReplyToItemID = inReplyToItemID?.rawValue
        payload = try WorldJSON.makeEncoder().encode(utterance)
    }

    var utterance: PersonUtterance {
        get throws {
            try WorldJSON.makeDecoder().decode(PersonUtterance.self, from: payload)
        }
    }
}
