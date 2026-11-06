import Foundation
import SwiftData
import WorldCore

/// SwiftData model for a locally cached conversation item.
///
/// This model mirrors `WorldCore.ConversationItem`. The complete DTO is stored as JSON so new
/// contract fields, including trace context and reply provenance, are not silently discarded.
@Model
final class ConversationItemModel {
    #Index<ConversationItemModel>([\.serverURI, \.createdAt])

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
        let encoded = try WorldJSON.makeEncoder().encode(item)
        guard encoded != payload else { return }
        conversationID = item.conversationID.rawValue
        createdAt = item.createdAt
        payload = encoded
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

/// How far the cache reaches on one server. See `ConversationSyncState`.
@Model
final class ConversationSyncStateModel {
    @Attribute(.unique) var serverURI: String
    var newestItemID: String?
    var oldestItemID: String?
    var reachedBeginning: Bool

    init(serverURI: String, state: ConversationSyncState) {
        self.serverURI = serverURI
        newestItemID = state.newestItemID?.rawValue
        oldestItemID = state.oldestItemID?.rawValue
        reachedBeginning = state.reachedBeginning
    }

    var state: ConversationSyncState {
        get {
            ConversationSyncState(
                newestItemID: newestItemID.flatMap { try? ConversationItemID(validating: $0) },
                oldestItemID: oldestItemID.flatMap { try? ConversationItemID(validating: $0) },
                reachedBeginning: reachedBeginning
            )
        }
        set {
            newestItemID = newValue.newestItemID?.rawValue
            oldestItemID = newValue.oldestItemID?.rawValue
            reachedBeginning = newValue.reachedBeginning
        }
    }
}
