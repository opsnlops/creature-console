import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

@Suite("Creature World MongoDB persistence provider")
struct MongoWorldPersistenceProviderTests {
    @Test("Connection failures leave the provider unhealthy and allow retries")
    func unavailableMongoDoesNotPreventRetries() async {
        let attempts = ConnectionAttemptCounter()
        let provider = MongoWorldPersistenceProvider(
            uri: CreatureWorldConfiguration.defaultMongoURI,
            logger: Logger(label: "creature-world-provider-tests"),
            connector: { _, _ in
                _ = await attempts.increment()
                throw TestConnectionError.unavailable
            }
        )

        await provider.connectIfNeeded()
        #expect(!(await provider.isHealthy()))
        await provider.connectIfNeeded()
        #expect(await attempts.value == 2)
    }

    @Test("Provider becomes healthy when MongoDB returns")
    func providerRecoversWithoutRestart() async {
        let attempts = ConnectionAttemptCounter()
        let provider = MongoWorldPersistenceProvider(
            uri: CreatureWorldConfiguration.defaultMongoURI,
            logger: Logger(label: "creature-world-provider-tests"),
            connector: { _, _ in
                let attempt = await attempts.increment()
                guard attempt > 1 else { throw TestConnectionError.unavailable }
                return MongoWorldPersistenceConnection(
                    isHealthy: { true },
                    shutdown: {}
                )
            }
        )

        await provider.connectIfNeeded()
        #expect(!(await provider.isHealthy()))

        await provider.connectIfNeeded()
        #expect(await provider.isHealthy())
        #expect(await attempts.value == 2)
    }

    @Test("A new persistence connection recovers timers before becoming healthy")
    func connectionRecoversTimersBeforePublication() async {
        let recoveries = ConnectionAttemptCounter()
        let provider = MongoWorldPersistenceProvider(
            uri: CreatureWorldConfiguration.defaultMongoURI,
            logger: Logger(label: "creature-world-provider-tests"),
            connector: { _, _ in
                MongoWorldPersistenceConnection(
                    isHealthy: { true },
                    recoverTimers: {
                        _ = await recoveries.increment()
                    },
                    shutdown: {}
                )
            }
        )

        await provider.connectIfNeeded()

        #expect(await recoveries.value == 1)
        #expect(await provider.isHealthy())
    }

    @Test("Timer recovery failure rejects and closes the candidate connection")
    func failedTimerRecoveryRejectsConnection() async {
        let shutdowns = ConnectionAttemptCounter()
        let provider = MongoWorldPersistenceProvider(
            uri: CreatureWorldConfiguration.defaultMongoURI,
            logger: Logger(label: "creature-world-provider-tests"),
            connector: { _, _ in
                MongoWorldPersistenceConnection(
                    isHealthy: { true },
                    recoverTimers: {
                        throw TestConnectionError.unavailable
                    },
                    shutdown: {
                        _ = await shutdowns.increment()
                    }
                )
            }
        )

        await provider.connectIfNeeded()

        #expect(!(await provider.isHealthy()))
        #expect(await shutdowns.value == 1)
    }

    @Test("Accepted conversation items wake matching subscribers")
    func acceptedConversationItemPublishesUpdate() async throws {
        let utterance = try PersonUtterance(
            utteranceID: UtteranceID(validating: "utterance:provider-stream"),
            conversationID: ConversationID(validating: "conversation:april-beaky"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Hello from another client",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: Date(timeIntervalSince1970: 1_789_100_002),
            confidence: 1
        )
        let item = try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:provider-stream"),
            conversationID: utterance.conversationID,
            authorID: utterance.speakerID,
            authorKind: .person,
            text: utterance.text,
            createdAt: utterance.occurredAt,
            utteranceID: utterance.utteranceID
        )
        let result = UtteranceIngressResult(
            disposition: .accepted,
            percept: try PersonUtterancePercept(
                characterID: utterance.addresseeIDs[0],
                utterance: utterance,
                priorConversationItems: []
            ),
            conversationItem: item
        )
        let provider = MongoWorldPersistenceProvider(
            uri: CreatureWorldConfiguration.defaultMongoURI,
            logger: Logger(label: "creature-world-provider-tests"),
            connector: { _, _ in
                MongoWorldPersistenceConnection(
                    isHealthy: { true },
                    ingestUtterance: { _ in result },
                    shutdown: {}
                )
            }
        )
        await provider.connectIfNeeded()
        let stream = try await provider.subscribe(to: utterance.conversationID)
        let received = Task<ConversationItem?, Never> {
            for await update in stream {
                if case .item(let item) = update {
                    return item
                }
            }
            return nil
        }

        _ = try await provider.ingest(utterance)

        #expect(await received.value == item)
    }

    @Test("Provider shutdown finishes conversation subscriptions")
    func shutdownFinishesConversationSubscriptions() async throws {
        let conversationID = try ConversationID(validating: "conversation:april-beaky")
        let provider = MongoWorldPersistenceProvider(
            uri: CreatureWorldConfiguration.defaultMongoURI,
            logger: Logger(label: "creature-world-provider-tests"),
            connector: { _, _ in
                MongoWorldPersistenceConnection(
                    isHealthy: { true },
                    shutdown: {}
                )
            }
        )
        await provider.connectIfNeeded()
        let stream = try await provider.subscribe(to: conversationID)
        let completion = Task<Void, Never> {
            for await _ in stream {}
        }

        await provider.shutdown()

        await completion.value
    }
}

private actor ConnectionAttemptCounter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private enum TestConnectionError: Error {
    case unavailable
}
