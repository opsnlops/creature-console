import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// Light readings as the house tells them: on a halving or doubling (`minimum_change_percent`
/// 50, floor 10 lux), or every fifteen minutes when the value has moved less.
@Suite("The daylight's arithmetic")
struct DaylightTrackerTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    /// Today at `hour`:`minute`, local.
    private func at(_ hour: Int, _ minute: Int, day: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let base = calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 10 + day, hour: hour, minute: minute))!
        return base
    }

    private func reading(_ lux: Double, _ hour: Int, _ minute: Int, day: Int = 0)
        -> DaylightTracker.Reading
    {
        DaylightTracker.Reading(lux: lux, at: at(hour, minute, day: day))
    }

    @Test("An October evening: dimming as the light halves, dusk once, as it falls through 100")
    func anEvening() {
        var tracker = DaylightTracker(zone: zone)
        // The first reading has nothing to compare with.
        #expect(tracker.observe(reading(1_800, 17, 40)) == .init(trend: nil, moment: nil))
        #expect(tracker.observe(reading(850, 17, 55)) == .init(trend: .dimming, moment: nil))
        #expect(tracker.observe(reading(400, 18, 5)) == .init(trend: .dimming, moment: nil))
        #expect(tracker.observe(reading(190, 18, 14)) == .init(trend: .dimming, moment: nil))
        // Through the line: dusk.
        #expect(tracker.observe(reading(90, 18, 22)) == .init(trend: .dimming, moment: .dusk))
        // On down, and a cloud breaking lifts it back over and under: still the one dusk.
        #expect(tracker.observe(reading(140, 18, 26)).moment == nil)
        #expect(tracker.observe(reading(60, 18, 31)).moment == nil)
        #expect(tracker.observe(reading(25, 18, 40)).moment == nil)
    }

    @Test("A morning: dawn once as the light rises through 100; brightening")
    func aMorning() {
        var tracker = DaylightTracker(zone: zone, seed: reading(0, 6, 40))
        #expect(tracker.observe(reading(30, 7, 5)).trend == .brightening)
        #expect(tracker.observe(reading(70, 7, 15)) == .init(trend: .brightening, moment: nil))
        #expect(tracker.observe(reading(160, 7, 24)) == .init(trend: .brightening, moment: .dawn))
        #expect(tracker.observe(reading(80, 7, 30)).moment == nil)
        #expect(tracker.observe(reading(200, 7, 35)).moment == nil)
    }

    @Test("A storm at midday is not dusk; clearing after noon is not dawn")
    func storms() {
        var tracker = DaylightTracker(zone: zone)
        _ = tracker.observe(reading(400, 11, 30))
        // Before noon, falling under the line is no dusk.
        #expect(tracker.observe(reading(80, 11, 40)).moment == nil)
        // After noon, rising over it is no dawn.
        #expect(tracker.observe(reading(300, 12, 20)).moment == nil)
    }

    @Test("A cloud at noon dims and passes: the trend compares with half an hour ago")
    func aCloud() {
        var tracker = DaylightTracker(zone: zone)
        _ = tracker.observe(reading(60_000, 12, 0))
        #expect(tracker.observe(reading(25_000, 12, 10)).trend == .dimming)
        // Back to where it was within the half hour: steady, against the first reading.
        #expect(tracker.observe(reading(61_000, 12, 20)).trend == .steady)
    }

    @Test("A reading over an hour after the last has nothing to compare with")
    func aLongGap() {
        var tracker = DaylightTracker(zone: zone, seed: reading(5_000, 9, 0))
        #expect(tracker.observe(reading(40_000, 10, 30)).trend == nil)
        // Only the last hour is kept.
        #expect(tracker.readings.count == 1)
    }

    @Test("A new day may have its own dusk")
    func dayByDay() {
        var tracker = DaylightTracker(zone: zone)
        _ = tracker.observe(reading(300, 18, 0))
        #expect(tracker.observe(reading(50, 18, 20)).moment == .dusk)
        _ = tracker.observe(reading(300, 17, 50, day: 1))
        #expect(tracker.observe(reading(50, 18, 10, day: 1)).moment == .dusk)
    }

    @Test("The trend is a ratio, so zeros do not divide by nothing")
    func ratios() {
        #expect(DaylightTracker.trend(from: 0, to: 0) == .steady)
        #expect(DaylightTracker.trend(from: 0, to: 4) == .brightening)
        #expect(DaylightTracker.trend(from: 1_000, to: 800) == .steady)
        #expect(DaylightTracker.trend(from: 1_000, to: 500) == .dimming)
    }
}

@Suite(
    "The daylight's rule",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct DaylightRuleTests {
    @Test("Seeded from the light the world knows, a reading renews the trend and crosses into dusk")
    func seedAndDusk() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "daylight-rule-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let evening = calendar.date(bySettingHour: 18, minute: 10, second: 0, of: Date())!
        let outside = try EntityID(validating: "place:outside-\(UUID().uuidString.lowercased())")
        try await persistence.facts.save(
            try Fact(
                subjectID: outside, predicate: "environment.light_lux", value: .number(240),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: evening.addingTimeInterval(-600), derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "house", version: "1")))

        let accepted = Accepted()
        let rule = DaylightRule(zone: zone, facts: persistence.facts) { await accepted.add($0) }
        try await rule.seed(now: evening)
        // Someone else's measurement, and a reading of something else, are not the light.
        try await rule.heard(
            try reading(outside, predicate: "temperature_f", value: 52, at: evening))
        #expect(await accepted.events.isEmpty)

        try await rule.heard(try reading(outside, predicate: "light_lux", value: 80, at: evening))
        let events = await accepted.events
        #expect(events.count == 2)
        let trend = try #require(events.first)
        #expect(trend.type == HouseEvents.measurementChanged)
        #expect(trend.payload["predicate"] == .string("light_trend"))
        #expect(trend.payload["value"] == .string("dimming"))
        #expect(trend.payload["valid_for_seconds"] == .number(DaylightTracker.trendLifetime))
        #expect(trend.epistemic.type == .inferred)
        let dusk = try #require(events.last)
        #expect(dusk.type == HouseEvents.dusk)
        #expect(dusk.subjectIDs == [outside])
        #expect(dusk.payload["lux"] == .number(80))
        #expect(Happening.isStoryworthy(dusk))
        #expect(!Happening.isStoryworthy(trend))
    }

    private func reading(
        _ place: EntityID, predicate: String, value: Double, at: Date
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: HouseEvents.measurementChanged, occurredAt: at,
            source: EventSource(
                id: SourceID(validating: "home-assistant:sensor.outside_light_level"),
                kind: "home-assistant"),
            subjectIDs: [place], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: ["predicate": .string(predicate), "value": .number(value)])
    }
}

private actor Accepted {
    var events: [WorldEventEnvelope] = []
    func add(_ event: WorldEventEnvelope) { events.append(event) }
}
