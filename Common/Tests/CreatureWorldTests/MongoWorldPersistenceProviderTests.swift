import Logging
import Testing

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
