import CreatureAppSupport
import Foundation
import SwiftData
import WorldCore

protocol CommunicatorConversationService: Sendable {
    func conversation() async throws -> [ConversationItem]
    func submit(text: String, inReplyTo item: ConversationItem?) async throws
    func updates() async throws -> WorldConversationUpdateStream
}

protocol CommunicatorWorldClient: Sendable {
    func submit(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult
    func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage
    func updates(in conversationID: ConversationID) throws -> WorldConversationUpdateStream
}

extension WorldConversationClient: CommunicatorWorldClient {}

extension CommunicatorWorldClient {
    func updates(in conversationID: ConversationID) throws -> WorldConversationUpdateStream {
        WorldConversationUpdateStream { $0.finish() }
    }
}

extension CommunicatorConversationService {
    func updates() async throws -> WorldConversationUpdateStream {
        WorldConversationUpdateStream { $0.finish() }
    }
}

protocol CommunicatorWorldClientProviding: Sendable {
    func serverURI() async -> String
    func client() async throws -> any CommunicatorWorldClient
}

extension CommunicatorWorldClientProviding {
    func serverURI() async -> String { "test://world" }
}

protocol ConversationPersistence: Sendable {
    func conversation(serverURI: String) async throws -> [ConversationItem]
    func latestCachedItemID(serverURI: String) async throws -> ConversationItemID?
    func pendingUtterances(serverURI: String) async throws -> [PersonUtterance]
    func enqueue(
        _ utterance: PersonUtterance,
        inReplyTo itemID: ConversationItemID?,
        serverURI: String
    ) async throws
    func accept(_ result: UtteranceIngressResult, serverURI: String) async throws
    func cache(_ items: [ConversationItem], serverURI: String) async throws
}

actor LiveCommunicatorConversationService: CommunicatorConversationService {
    private let persistence: any ConversationPersistence
    private let clientProvider: any CommunicatorWorldClientProviding
    private var synchronizedServerURIs: Set<String> = []

    init(
        persistence: any ConversationPersistence,
        clientProvider: any CommunicatorWorldClientProviding
    ) {
        self.persistence = persistence
        self.clientProvider = clientProvider
    }

    func conversation() async throws -> [ConversationItem] {
        let serverURI = await clientProvider.serverURI()
        await synchronizeBestEffort(serverURI: serverURI)
        return try await persistence.conversation(serverURI: serverURI)
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
        let serverURI = await clientProvider.serverURI()
        try await persistence.enqueue(
            utterance,
            inReplyTo: item?.itemID,
            serverURI: serverURI
        )
        await synchronizeBestEffort(serverURI: serverURI)
    }

    func updates() async throws -> WorldConversationUpdateStream {
        let client = try await clientProvider.client()
        return try client.updates(in: ConversationIdentity.conversationID)
    }

    private func synchronizeBestEffort(serverURI: String) async {
        do {
            let client = try await clientProvider.client()
            // Capture the cursor before flushing the outbox. A remote turn may have arrived while
            // this client was offline; using the newly accepted local item as the cursor would skip
            // that turn.
            let cursor =
                synchronizedServerURIs.contains(serverURI)
                ? try await persistence.latestCachedItemID(serverURI: serverURI)
                : nil
            for utterance in try await persistence.pendingUtterances(serverURI: serverURI) {
                try await persistence.accept(
                    client.submit(utterance),
                    serverURI: serverURI
                )
            }
            do {
                try await synchronizeHistory(
                    using: client,
                    after: cursor,
                    serverURI: serverURI
                )
            } catch  where cursor != nil {
                // The canonical history may have been replaced while this client was offline.
                // Starting over is safe because cache writes are idempotent by item ID.
                try await synchronizeHistory(
                    using: client,
                    after: nil,
                    serverURI: serverURI
                )
            }
            synchronizedServerURIs.insert(serverURI)
        } catch {
            // The durable outbox and local cache remain available until the next synchronization.
        }
    }

    private func synchronizeHistory(
        using client: any CommunicatorWorldClient,
        after initialCursor: ConversationItemID?,
        serverURI: String
    ) async throws {
        var cursor = initialCursor
        repeat {
            let page = try await client.items(
                in: ConversationIdentity.conversationID,
                after: cursor,
                limit: 100
            )
            try await persistence.cache(page.items, serverURI: serverURI)
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

extension Notification.Name {
    static let communicatorConversationCacheCleared = Notification.Name(
        "communicatorConversationCacheCleared"
    )
}

@MainActor
enum ConversationCacheMaintenance {
    static func clear(using modelContext: ModelContext) throws {
        for item in try modelContext.fetch(FetchDescriptor<ConversationItemModel>()) {
            modelContext.delete(item)
        }
        try modelContext.save()
        NotificationCenter.default.post(name: .communicatorConversationCacheCleared, object: nil)
    }
}

@ModelActor
actor SwiftDataConversationRepository: ConversationPersistence {
    func conversation(serverURI: String) throws -> [ConversationItem] {
        let stored = try fetchConversationModels(serverURI: serverURI).map { try $0.item }
        let pending = try fetchPendingModels(serverURI: serverURI).map {
            try provisionalItem(for: $0)
        }
        return (stored + pending).sorted(by: Self.ordersBefore)
    }

    func pendingUtterances(serverURI: String) throws -> [PersonUtterance] {
        try fetchPendingModels(serverURI: serverURI).map { try $0.utterance }
    }

    func latestCachedItemID(serverURI: String) throws -> ConversationItemID? {
        var descriptor = FetchDescriptor<ConversationItemModel>(
            predicate: #Predicate { $0.serverURI == serverURI },
            sortBy: [
                SortDescriptor(\ConversationItemModel.createdAt, order: .reverse),
                SortDescriptor(\ConversationItemModel.id, order: .reverse),
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { try $0.item.itemID }
    }

    func enqueue(
        _ utterance: PersonUtterance,
        inReplyTo itemID: ConversationItemID?,
        serverURI: String
    ) throws {
        modelContext.insert(
            try PendingUtteranceModel(
                utterance: utterance,
                inReplyToItemID: itemID,
                serverURI: serverURI
            )
        )
        try modelContext.save()
    }

    func accept(_ result: UtteranceIngressResult, serverURI: String) throws {
        try upsert(result.conversationItem, serverURI: serverURI)
        let storageID = PendingUtteranceModel.storageID(
            serverURI: serverURI,
            utteranceID: result.percept.utterance.utteranceID
        )
        var descriptor = FetchDescriptor<PendingUtteranceModel>(
            predicate: #Predicate { $0.id == storageID }
        )
        descriptor.fetchLimit = 1
        if let pending = try modelContext.fetch(descriptor).first {
            modelContext.delete(pending)
        }
        try modelContext.save()
    }

    func cache(_ items: [ConversationItem], serverURI: String) throws {
        for item in items {
            try upsert(item, serverURI: serverURI)
        }
        try modelContext.save()
    }

    private func fetchConversationModels(serverURI: String) throws -> [ConversationItemModel] {
        let descriptor = FetchDescriptor<ConversationItemModel>(
            predicate: #Predicate { $0.serverURI == serverURI },
            sortBy: [
                SortDescriptor(\ConversationItemModel.createdAt),
                SortDescriptor(\ConversationItemModel.id),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchPendingModels(serverURI: String) throws -> [PendingUtteranceModel] {
        try modelContext.fetch(
            FetchDescriptor<PendingUtteranceModel>(
                predicate: #Predicate { $0.serverURI == serverURI },
                sortBy: [
                    SortDescriptor(\PendingUtteranceModel.occurredAt),
                    SortDescriptor(\PendingUtteranceModel.id),
                ]
            )
        )
    }

    private func upsert(_ item: ConversationItem, serverURI: String) throws {
        let storageID = ConversationItemModel.storageID(
            serverURI: serverURI,
            itemID: item.itemID
        )
        var descriptor = FetchDescriptor<ConversationItemModel>(
            predicate: #Predicate { $0.id == storageID }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            try existing.update(with: item)
        } else {
            modelContext.insert(try ConversationItemModel(item: item, serverURI: serverURI))
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
