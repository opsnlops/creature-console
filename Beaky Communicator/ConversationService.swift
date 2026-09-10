import CreatureAppSupport
import Foundation
import SwiftData
import WorldCore

protocol CommunicatorConversationService: Sendable {
    func conversation() async throws -> [ConversationItem]
    func submit(text: String, inReplyTo item: ConversationItem?) async throws
}

protocol CommunicatorWorldClient: Sendable {
    func submit(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult
    func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage
}

extension WorldConversationClient: CommunicatorWorldClient {}

protocol CommunicatorWorldClientProviding: Sendable {
    func client() async throws -> any CommunicatorWorldClient
}

protocol ConversationPersistence: Sendable {
    func conversation() async throws -> [ConversationItem]
    func latestCachedItemID() async throws -> ConversationItemID?
    func pendingUtterances() async throws -> [PersonUtterance]
    func enqueue(_ utterance: PersonUtterance, inReplyTo itemID: ConversationItemID?) async throws
    func accept(_ result: UtteranceIngressResult) async throws
    func cache(_ items: [ConversationItem]) async throws
}

actor LiveCommunicatorConversationService: CommunicatorConversationService {
    private let persistence: any ConversationPersistence
    private let clientProvider: any CommunicatorWorldClientProviding
    private var completedInitialHistorySync = false

    init(
        persistence: any ConversationPersistence,
        clientProvider: any CommunicatorWorldClientProviding
    ) {
        self.persistence = persistence
        self.clientProvider = clientProvider
    }

    func conversation() async throws -> [ConversationItem] {
        await synchronizeBestEffort()
        return try await persistence.conversation()
    }

    func submit(text: String, inReplyTo item: ConversationItem?) async throws {
        let utterance = try PersonUtterance(
            conversationID: ConversationIdentity.conversationID,
            speakerID: ConversationIdentity.aprilID,
            addresseeIDs: [ConversationIdentity.beakyID],
            inResponseToResponseID: item?.responseID,
            text: text,
            modality: .typed,
            source: item == nil ? .communicatorComposition : .communicatorReply,
            sourceID: ConversationIdentity.sourceID,
            occurredAt: Date(),
            confidence: 1
        )
        try await persistence.enqueue(utterance, inReplyTo: item?.itemID)
        await synchronizeBestEffort()
    }

    private func synchronizeBestEffort() async {
        do {
            let client = try await clientProvider.client()
            // Capture the cursor before flushing the outbox. A remote turn may have arrived while
            // this client was offline; using the newly accepted local item as the cursor would skip
            // that turn.
            let cursor =
                completedInitialHistorySync
                ? try await persistence.latestCachedItemID()
                : nil
            for utterance in try await persistence.pendingUtterances() {
                try await persistence.accept(client.submit(utterance))
            }
            do {
                try await synchronizeHistory(using: client, after: cursor)
            } catch  where cursor != nil {
                // The canonical history may have been replaced while this client was offline.
                // Starting over is safe because cache writes are idempotent by item ID.
                try await synchronizeHistory(using: client, after: nil)
            }
            completedInitialHistorySync = true
        } catch {
            // The durable outbox and local cache remain available until the next synchronization.
        }
    }

    private func synchronizeHistory(
        using client: any CommunicatorWorldClient,
        after initialCursor: ConversationItemID?
    ) async throws {
        var cursor = initialCursor
        repeat {
            let page = try await client.items(
                in: ConversationIdentity.conversationID,
                after: cursor,
                limit: 100
            )
            try await persistence.cache(page.items)
            guard page.hasMore else { break }
            guard let next = page.nextItemID, next != cursor else {
                throw ConversationSynchronizationError.invalidPaginationCursor
            }
            cursor = next
        } while true
    }
}

private enum ConversationSynchronizationError: Error {
    case invalidPaginationCursor
}

@ModelActor
actor SwiftDataConversationRepository: ConversationPersistence {
    func conversation() throws -> [ConversationItem] {
        let stored = try fetchConversationModels().map { try $0.item }
        let pending = try fetchPendingModels().map { try provisionalItem(for: $0) }
        return (stored + pending).sorted(by: Self.ordersBefore)
    }

    func pendingUtterances() throws -> [PersonUtterance] {
        try fetchPendingModels().map { try $0.utterance }
    }

    func latestCachedItemID() throws -> ConversationItemID? {
        var descriptor = FetchDescriptor<ConversationItemModel>(
            sortBy: [
                SortDescriptor(\ConversationItemModel.createdAt, order: .reverse),
                SortDescriptor(\ConversationItemModel.id, order: .reverse),
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map {
            try ConversationItemID(validating: $0.id)
        }
    }

    func enqueue(
        _ utterance: PersonUtterance,
        inReplyTo itemID: ConversationItemID?
    ) throws {
        modelContext.insert(
            try PendingUtteranceModel(utterance: utterance, inReplyToItemID: itemID)
        )
        try modelContext.save()
    }

    func accept(_ result: UtteranceIngressResult) throws {
        try upsert(result.conversationItem)
        let utteranceID = result.percept.utterance.utteranceID.rawValue
        var descriptor = FetchDescriptor<PendingUtteranceModel>(
            predicate: #Predicate { $0.id == utteranceID }
        )
        descriptor.fetchLimit = 1
        if let pending = try modelContext.fetch(descriptor).first {
            modelContext.delete(pending)
        }
        try modelContext.save()
    }

    func cache(_ items: [ConversationItem]) throws {
        for item in items {
            try upsert(item)
        }
        try modelContext.save()
    }

    private func fetchConversationModels() throws -> [ConversationItemModel] {
        let descriptor = FetchDescriptor<ConversationItemModel>(
            sortBy: [
                SortDescriptor(\ConversationItemModel.createdAt),
                SortDescriptor(\ConversationItemModel.id),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchPendingModels() throws -> [PendingUtteranceModel] {
        try modelContext.fetch(
            FetchDescriptor<PendingUtteranceModel>(
                sortBy: [
                    SortDescriptor(\PendingUtteranceModel.occurredAt),
                    SortDescriptor(\PendingUtteranceModel.id),
                ]
            )
        )
    }

    private func upsert(_ item: ConversationItem) throws {
        let itemID = item.itemID.rawValue
        var descriptor = FetchDescriptor<ConversationItemModel>(
            predicate: #Predicate { $0.id == itemID }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            try existing.update(with: item)
        } else {
            modelContext.insert(try ConversationItemModel(item: item))
        }
    }

    private func provisionalItem(for pending: PendingUtteranceModel) throws -> ConversationItem {
        let utterance = try pending.utterance
        return try ConversationItem(
            itemID: ConversationItemID(
                validating: "conversation-item:\(utterance.utteranceID.rawValue)"
            ),
            conversationID: utterance.conversationID,
            authorID: utterance.speakerID,
            authorKind: .person,
            text: utterance.text,
            createdAt: utterance.occurredAt,
            inReplyToItemID: try pending.inReplyToItemID.map(ConversationItemID.init(validating:)),
            utteranceID: utterance.utteranceID,
            trace: utterance.trace
        )
    }

    private static func ordersBefore(_ lhs: ConversationItem, _ rhs: ConversationItem) -> Bool {
        (lhs.createdAt, lhs.itemID.rawValue) < (rhs.createdAt, rhs.itemID.rawValue)
    }
}

private enum ConversationIdentity {
    static let conversationID = try! ConversationID(validating: "conversation:april-beaky")
    static let aprilID = try! EntityID(validating: "person:april")
    static let beakyID = try! EntityID(validating: "character:beaky")
    static let sourceID = try! SourceID(validating: "communicator:beaky-app")
}
