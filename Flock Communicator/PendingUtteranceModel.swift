import Foundation
import SwiftData
import WorldCore

/// SwiftData outbox entry for a person utterance awaiting canonical server acceptance.
@Model
final class PendingUtteranceModel {
    /// SwiftData's unique storage identity. The canonical utterance ID remains inside `payload`.
    @Attribute(.unique) var id: String
    var serverURI: String = ""
    var conversationID: String
    var occurredAt: Date
    var inReplyToItemID: String?
    var payload: Data

    init(
        utterance: PersonUtterance,
        inReplyToItemID: ConversationItemID?,
        serverURI: String
    ) throws {
        id = Self.storageID(serverURI: serverURI, utteranceID: utterance.utteranceID)
        self.serverURI = serverURI
        conversationID = utterance.conversationID.rawValue
        occurredAt = utterance.occurredAt
        self.inReplyToItemID = inReplyToItemID?.rawValue
        payload = try WorldJSON.makeEncoder().encode(utterance)
    }

    static func storageID(serverURI: String, utteranceID: UtteranceID) -> String {
        "\(serverURI)\n\(utteranceID.rawValue)"
    }

    var utterance: PersonUtterance {
        get throws {
            try WorldJSON.makeDecoder().decode(PersonUtterance.self, from: payload)
        }
    }
}
