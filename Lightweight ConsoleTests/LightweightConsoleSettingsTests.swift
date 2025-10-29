import Foundation
import Testing

@testable import Lightweight_Console

@Suite("Lightweight settings")
struct LightweightSettingsStoreTests {

    @Test("round-trips settings and token")
    func roundTripSettings() async throws {
        let suiteName = "LightweightSettings-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "DefaultsInit", code: 0)
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = LightweightSettingsStore(defaults: defaults)

        var defaultsSnapshot = await store.currentSettings()
        #expect(defaultsSnapshot.hostname == "proxy.prod.chirpchirp.dev")
        #expect(defaultsSnapshot.port == 443)
        #expect(defaultsSnapshot.useTLS)
        #expect(defaultsSnapshot.apiKey.isEmpty)

        let updated = LightweightClientSettings(
            hostname: "test.proxy",
            port: 8443,
            useTLS: false,
            defaultCreatureId: "creature-01",
            backendHostname: "creature.local",
            apiKey: "abc123"
        )

        await store.update(settings: updated)
        await store.setAuthToken("abc123")
        await store.setActiveUniverse(42)

        defaultsSnapshot = await store.currentSettings()
        #expect(defaultsSnapshot == updated)
        #expect(defaultsSnapshot.apiKey == "abc123")
        let token = await store.authToken()
        #expect(token == "abc123")
        let universe = await store.activeUniverse()
        #expect(universe == 42)
        let scopedUniverse = defaults.integer(forKey: "lightweight.activeUniverse")
        let sharedUniverse = defaults.integer(forKey: "activeUniverse")
        #expect(scopedUniverse == 42)
        #expect(sharedUniverse == 42)

        await store.setAuthToken("")
        let cleared = await store.authToken()
        #expect(cleared.isEmpty)
        let clearedSnapshot = await store.currentSettings()
        #expect(clearedSnapshot.apiKey.isEmpty)
    }

    @Test("active universe falls back to shared key")
    func activeUniverseFallsBack() async throws {
        let suiteName = "LightweightSettings-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "DefaultsInit", code: 0)
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(27, forKey: "activeUniverse")
        let store = LightweightSettingsStore(defaults: defaults)
        let universe = await store.activeUniverse()
        #expect(universe == 27)
    }

    @Test("scoped universe overrides shared value")
    func scopedUniverseOverridesShared() async throws {
        let suiteName = "LightweightSettings-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "DefaultsInit", code: 0)
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(27, forKey: "activeUniverse")
        defaults.set(12, forKey: "lightweight.activeUniverse")
        let store = LightweightSettingsStore(defaults: defaults)
        let universe = await store.activeUniverse()
        #expect(universe == 12)
    }
}
