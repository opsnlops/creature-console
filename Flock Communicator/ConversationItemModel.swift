import Foundation
import SwiftData
import WorldCore

/// SwiftData model for a locally cached conversation item.
///
/// This model mirrors `WorldCore.ConversationItem`. The complete DTO is stored as JSON so new
/// contract fields, including trace context and reply provenance, are not silently discarded.
@Model
final class ConversationItemModel {
    /// SwiftData's unique storage identity. The canonical item ID remains inside `payload`.
    @Attribute(.unique) var id: String
    var serverURI: String = ""
    var conversationID: String
    var createdAt: Date
    var payload: Data

    init(item: ConversationItem, serverURI: String) throws {
        id = Self.storageID(serverURI: serverURI, itemID: item.itemID)
        self.serverURI = serverURI
        conversationID = item.conversationID.rawValue
        createdAt = item.createdAt
        payload = try WorldJSON.makeEncoder().encode(item)
    }

    static func storageID(serverURI: String, itemID: ConversationItemID) -> String {
        "\(serverURI)\n\(itemID.rawValue)"
    }

    func update(with item: ConversationItem) throws {
        conversationID = item.conversationID.rawValue
        createdAt = item.createdAt
        payload = try WorldJSON.makeEncoder().encode(item)
    }

    var item: ConversationItem {
        get throws {
            do {
                return try WorldJSON.makeDecoder().decode(ConversationItem.self, from: payload)
            } catch {
                // Builds before the World API stored Foundation's numeric Date representation.
                return try JSONDecoder().decode(ConversationItem.self, from: payload)
            }
        }
    }
}
