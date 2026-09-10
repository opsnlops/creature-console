import Foundation
import WorldCore

enum ConversationStreamUpdate: Sendable {
    case item(ConversationItem)
    case heartbeat
}

typealias ConversationItemStream = AsyncStream<ConversationStreamUpdate>

actor ConversationUpdateBroker {
    private let maximumSubscriptions: Int
    private let heartbeatInterval: Duration
    private var subscriptions: [UUID: Subscription] = [:]
    private var heartbeatTasks: [UUID: Task<Void, Never>] = [:]

    init(maximumSubscriptions: Int = 256, heartbeatInterval: Duration = .seconds(15)) {
        precondition(maximumSubscriptions > 0)
        self.maximumSubscriptions = maximumSubscriptions
        self.heartbeatInterval = heartbeatInterval
    }

    func subscribe(to conversationID: ConversationID) throws -> ConversationItemStream {
        guard subscriptions.count < maximumSubscriptions else {
            throw WorldSubscriptionError.subscriptionLimitReached(limit: maximumSubscriptions)
        }
        let subscriptionID = UUID()
        let stream = ConversationItemStream(bufferingPolicy: .bufferingNewest(1)) {
            continuation in
            subscriptions[subscriptionID] = Subscription(
                conversationID: conversationID,
                continuation: continuation
            )
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.remove(subscriptionID) }
            }
        }
        heartbeatTasks[subscriptionID] = Task { [weak self, heartbeatInterval] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: heartbeatInterval)
                    await self?.heartbeat(subscriptionID)
                }
            } catch {
                // Cancellation ends heartbeat delivery for this subscription.
            }
        }
        return stream
    }

    func publish(_ item: ConversationItem) {
        var terminated: [UUID] = []
        for (subscriptionID, subscription) in subscriptions
        where subscription.conversationID == item.conversationID {
            if case .terminated = subscription.continuation.yield(.item(item)) {
                terminated.append(subscriptionID)
            }
        }
        for subscriptionID in terminated {
            remove(subscriptionID)
        }
    }

    func finish() {
        for continuation in subscriptions.values.map(\.continuation) {
            continuation.finish()
        }
        subscriptions.removeAll()
        for task in heartbeatTasks.values {
            task.cancel()
        }
        heartbeatTasks.removeAll()
    }

    private func heartbeat(_ subscriptionID: UUID) {
        guard let subscription = subscriptions[subscriptionID] else { return }
        if case .terminated = subscription.continuation.yield(.heartbeat) {
            remove(subscriptionID)
        }
    }

    private func remove(_ subscriptionID: UUID) {
        subscriptions.removeValue(forKey: subscriptionID)
        heartbeatTasks.removeValue(forKey: subscriptionID)?.cancel()
    }

    private struct Subscription: Sendable {
        let conversationID: ConversationID
        let continuation: ConversationItemStream.Continuation
    }
}
