import Foundation
import SwiftData
import WorldCore

/// SwiftData model for a locally cached conversation item.
///
/// This model mirrors `WorldCore.ConversationItem`. The complete DTO is stored as JSON so new
/// contract fields, including trace context and reply provenance, are not silently discarded.
@Model
final class ConversationItemModel {
    @Attribute(.unique) var id: String
    var conversationID: String
    var createdAt: Date
    var payload: Data

    init(item: ConversationItem) throws {
        id = item.itemID.rawValue
        conversationID = item.conversationID.rawValue
        createdAt = item.createdAt
        payload = try JSONEncoder().encode(item)
    }

    var item: ConversationItem {
        get throws {
            try JSONDecoder().decode(ConversationItem.self, from: payload)
        }
    }
}
