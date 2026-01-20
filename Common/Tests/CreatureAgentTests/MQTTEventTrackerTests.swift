import Testing

@testable import creature_agent

@Suite("CreatureAgent MQTTEventTracker")
struct MQTTEventTrackerTests {
    @Test("Skips missing timestamps")
    func skipsMissingTimestamp() async {
        let tracker = MQTTEventTracker(logger: .init(label: "test"))
        let shouldProcess = await tracker.shouldProcess(topic: "home/alerts", timestamp: nil)
        #expect(shouldProcess == false)
    }

    @Test("Accepts first timestamp and rejects duplicates")
    func acceptsFirstTimestamp() async {
        let tracker = MQTTEventTracker(logger: .init(label: "test"))
        let first = await tracker.shouldProcess(topic: "home/alerts", timestamp: 100)
        let duplicate = await tracker.shouldProcess(topic: "home/alerts", timestamp: 100)
        let older = await tracker.shouldProcess(topic: "home/alerts", timestamp: 99)
        let newer = await tracker.shouldProcess(topic: "home/alerts", timestamp: 101)

        #expect(first == true)
        #expect(duplicate == false)
        #expect(older == false)
        #expect(newer == true)
    }

    @Test("Retained baseline does not block later updates")
    func retainedBaselineAllowsLiveUpdates() async {
        let tracker = MQTTEventTracker(logger: .init(label: "test"))
        await tracker.updateInitialTimestamp(for: "home/alerts", timestamp: 100)
        let shouldProcess = await tracker.shouldProcess(topic: "home/alerts", timestamp: 110)
        #expect(shouldProcess == true)
    }

    @Test("Initial timestamp only moves forward")
    func initialTimestampMovesForward() async {
        let tracker = MQTTEventTracker(logger: .init(label: "test"))
        await tracker.updateInitialTimestamp(for: "home/alerts", timestamp: 50)
        await tracker.updateInitialTimestamp(for: "home/alerts", timestamp: 40)
        let current = await tracker.initialTimestamp(for: "home/alerts")
        await tracker.updateInitialTimestamp(for: "home/alerts", timestamp: 60)
        let updated = await tracker.initialTimestamp(for: "home/alerts")

        #expect(current == 50)
        #expect(updated == 60)
    }

    @Test("Converts millisecond timestamps")
    func convertsMillisecondTimestamps() {
        let millis = "1768880656153"
        let seconds = MQTTEventTracker.timestamp(from: millis)
        #expect(seconds == 1_768_880_656.153)
    }
}
