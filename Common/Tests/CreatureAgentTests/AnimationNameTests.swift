import Common
import Foundation
import NIOConcurrencyHelpers
import Testing

@testable import creature_mqtt

/// The animation a creature is playing, by name (#267): a bird's spoken line is an ad-hoc
/// animation, a name fetched later is published once it arrives, and a lookup that found
/// nothing is asked again rather than remembered as "-unknown-".
@Suite("The name of the animation a creature is playing", .timeLimit(.minutes(1)))
struct AnimationNameTests {
    private func activity(_ animationID: String, reason: String) throws -> CreatureActivity {
        let json = """
            {"creature_id": "mango-1", "creature_name": "Mango", "state": "running",
             "animation_id": "\(animationID)", "reason": "\(reason)",
             "timestamp": "2026-10-24T03:00:00Z"}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CreatureActivity.self, from: Data(json.utf8))
    }

    /// Waits, a little at a time, until `condition` holds or the time is up.
    private func eventually(_ condition: () async -> Bool) async throws -> Bool {
        for _ in 0..<400 {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    @Test("A lookup that found nothing is asked again, and a found name is handed over")
    func failureIsNotRemembered() async throws {
        let resolver = AnimationNameResolver(retryAfter: 0)
        let asked = NIOLockedValueBox(0)
        let answer = NIOLockedValueBox<String?>(nil)
        let resolved = NIOLockedValueBox<[String]>([])
        let fetch: @Sendable (AnimationIdentifier) async -> String? = { _ in
            asked.withLockedValue { $0 += 1 }
            return answer.withLockedValue { $0 }
        }
        #expect(resolver.resolve(id: "speech-1", fetchIfMissing: fetch) == "-unknown-")
        #expect(try await eventually { asked.withLockedValue { $0 } == 1 })
        // Nothing found, and nothing cached: asked again.
        answer.withLockedValue { $0 = "Mango - 20:00 - hello" }
        #expect(
            try await eventually {
                _ = resolver.resolve(
                    id: "speech-1", fetchIfMissing: fetch,
                    whenResolved: { name in resolved.withLockedValue { $0.append(name) } })
                return !resolved.withLockedValue { $0 }.isEmpty
            })
        #expect(resolved.withLockedValue { $0 }.first == "Mango - 20:00 - hello")
        #expect(resolver.resolve(id: "speech-1", fetchIfMissing: fetch) == "Mango - 20:00 - hello")
    }

    @Test("A bird's spoken line is looked up as ad-hoc, and its name published once found")
    func spokenLineGetsItsName() async throws {
        let stub = StubMQTTPublisher()
        let reasons = NIOLockedValueBox<[ActivityReason?]>([])
        let processor = MQTTMessageProcessor(
            mqttClient: stub, logLevel: .critical, nameResolver: CreatureNameResolver(),
            fetchCreatureName: { _ in nil }, animationNameResolver: AnimationNameResolver(),
            fetchAnimationName: { _, reason in
                reasons.withLockedValue { $0.append(reason) }
                return "Mango - 20:00 - packets on the wire"
            },
            reloadAnimationNames: { [:] }, retainMessages: false)

        await processor.processCreatureActivity(try activity("speech-2", reason: "ad_hoc"))

        func names() async -> [String] {
            await stub.publishedMessages.filter { $0.components.last == "animation_name" }
                .map(\.value)
        }
        #expect(
            try await eventually { await names().contains("Mango - 20:00 - packets on the wire") })
        #expect(await names().contains("-unknown-"))
        #expect(reasons.withLockedValue { $0 } == [.adHoc])
    }

    @Test("A name that arrives after the creature moved on is not published")
    func lateNameForAnotherAnimation() async throws {
        let stub = StubMQTTPublisher()
        let gate = AsyncStream<Void>.makeStream()
        let processor = MQTTMessageProcessor(
            mqttClient: stub, logLevel: .critical, nameResolver: CreatureNameResolver(),
            fetchCreatureName: { _ in nil },
            animationNameResolver: AnimationNameResolver(initialNames: ["wave": "Wave"]),
            fetchAnimationName: { id, _ in
                // The spoken line's name comes late.
                for await _ in gate.stream { break }
                return "Mango - 20:01 - \(id)"
            },
            reloadAnimationNames: { [:] }, retainMessages: false)

        await processor.processCreatureActivity(try activity("speech-3", reason: "ad_hoc"))
        await processor.processCreatureActivity(try activity("wave", reason: "play"))
        func names() async -> [String] {
            await stub.publishedMessages.filter { $0.components.last == "animation_name" }
                .map(\.value)
        }
        #expect(try await eventually { await names().contains("Wave") })
        gate.continuation.yield()
        gate.continuation.finish()
        // Give the late name every chance to land; it must not.
        try await Task.sleep(for: .milliseconds(200))
        #expect(!(await names()).contains("Mango - 20:01 - speech-3"))
        #expect(await names().last == "Wave")
    }
}
