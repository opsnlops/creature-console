import CoreLocation
import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("What the sky will do, as facts")
struct WeatherFactsTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!
    // 2026-09-15 10:00 PDT
    private let now = Date(timeIntervalSince1970: 1_789_491_600)

    private func snapshot(rainAt hourOffset: Int? = nil, alert: Bool = false) -> WeatherSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let hours = (0..<48).map { offset in
            WeatherSnapshot.Hour(
                date: now.addingTimeInterval(TimeInterval(offset) * 3_600),
                rainChance: offset == hourOffset ? 0.7 : 0.05,
                condition: offset >= 8 && offset < 14 ? "Cloudy" : "Clear")
        }
        return WeatherSnapshot(
            days: [
                WeatherSnapshot.Day(
                    date: today, condition: "Partly cloudy", highF: 61.4, lowF: 51.6,
                    rainChance: 0.3, rainInches: 0.22,
                    sunrise: today.addingTimeInterval(6 * 3_600 + 52 * 60),
                    sunset: today.addingTimeInterval(19 * 3_600 + 21 * 60)),
                WeatherSnapshot.Day(
                    date: tomorrow, condition: "Rain", highF: 57, lowF: 49, rainChance: 0.85,
                    rainInches: 0.6, sunrise: nil, sunset: nil),
            ],
            hours: hours,
            alerts: alert
                ? [
                    WeatherSnapshot.Alert(
                        id: "a", summary: "Wind Advisory", severity: "moderate",
                        expires: now.addingTimeInterval(8 * 3_600))
                ] : [])
    }

    @Test("Today and tomorrow in a bird's words, whole degrees, a chance of rain when it matters")
    func daysBecomeLines() {
        let facts = WeatherFacts.facts(from: snapshot(), now: now, zone: pacific)
        let byPredicate = Dictionary(uniqueKeysWithValues: facts.map { ($0.predicate, $0) })
        #expect(
            byPredicate["forecast.today"]?.value
                == .string(
                    "Partly cloudy, high 61°, low 52°, 30% chance of rain (about a quarter inch)"))
        #expect(byPredicate["forecast.today.high_f"]?.value == .number(61))
        #expect(byPredicate["forecast.today.rain_in"]?.value == .number(0.22))
        #expect(
            byPredicate["forecast.tomorrow"]?.value
                == .string("Rain, high 57°, low 49°, 85% chance of rain (about an inch)"))
        #expect(byPredicate["sun.rise"]?.value == .string("6:52 AM"))
        #expect(byPredicate["sun.set"]?.value == .string("7:21 PM"))
        // Today's facts hold until midnight tonight; tomorrow's until midnight tomorrow.
        #expect(
            byPredicate["forecast.today"]?.validUntil == Date(timeIntervalSince1970: 1_789_542_000))
        #expect(
            byPredicate["forecast.tomorrow"]?.validUntil
                == Date(timeIntervalSince1970: 1_789_628_400))
        #expect(byPredicate["weather.alert"] == nil)
    }

    @Test("Next rain is said in human terms and holds only until it comes")
    func nextRain() {
        let dry = WeatherFacts.facts(from: snapshot(), now: now, zone: pacific)
        #expect(
            dry.first { $0.predicate == "forecast.next_rain" }?.value
                == .string("not in the next two days"))
        // 10 AM + 8 h = 6 PM today.
        let evening = WeatherFacts.facts(from: snapshot(rainAt: 8), now: now, zone: pacific)
        let fact = evening.first { $0.predicate == "forecast.next_rain" }
        #expect(fact?.value == .string("this evening around 6 PM, 70% chance"))
        #expect(fact?.validUntil == now.addingTimeInterval(8 * 3_600))
        // 10 AM + 23 h = 9 AM tomorrow.
        let morning = WeatherFacts.facts(from: snapshot(rainAt: 23), now: now, zone: pacific)
        #expect(
            morning.first { $0.predicate == "forecast.next_rain" }?.value
                == .string("tomorrow morning around 9 AM, 70% chance"))
    }

    @Test("Tonight is the evening hours summed up; an alert holds until it expires")
    func tonightAndAlerts() {
        let facts = WeatherFacts.facts(
            from: snapshot(rainAt: 9, alert: true), now: now, zone: pacific)
        #expect(
            facts.first { $0.predicate == "forecast.tonight" }?.value
                == .string("Cloudy, 70% chance of rain"))
        let alert = facts.first { $0.predicate == "weather.alert" }
        #expect(alert?.value == .string("Wind Advisory (moderate)"))
        #expect(alert?.validUntil == now.addingTimeInterval(8 * 3_600))
    }

    @Test("The source casts a fact only when its value changes")
    func castsOnChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "weather-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let casts = Casts()
        let readings = Readings(first: snapshot(), then: snapshot(rainAt: 8))
        let source = WeatherSource(
            place: try EntityID(validating: "place:outside"), latitude: 48.0, longitude: -122.5,
            zone: pacific, directory: directory,
            fetch: { _ in await readings.next() }
        ) { await casts.note($0) }
        await source.poll(now: now)
        let first = await casts.events.count
        #expect(first == 13)  // today ×5, sun ×2, tomorrow ×4, tonight, next rain
        await source.poll(now: now.addingTimeInterval(60))
        #expect(await casts.events.count == first)  // the same sky, nothing to say
        await source.poll(now: now.addingTimeInterval(120))
        let changed = await casts.events.dropFirst(first)
        #expect(changed.count == 2)  // next_rain and tonight moved; the rest stood
        #expect(
            Set(
                changed.compactMap {
                    if case .string(let p)? = $0.payload["predicate"] { p } else { nil }
                })
                == ["forecast.next_rain", "forecast.tonight"])
        // Every cast carries the source and a window.
        #expect(await casts.events.allSatisfy { $0.source.id.rawValue == "bridge:weather" })
        #expect(await casts.events.allSatisfy { $0.payload["valid_to"] != nil })
        #expect(await source.status.state == .on)
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

/// The sky as the test tells it: the first reading twice, then the second.
private actor Readings {
    private var queue: [WeatherSnapshot]
    private let last: WeatherSnapshot
    init(first: WeatherSnapshot, then: WeatherSnapshot) {
        queue = [first, first]
        last = then
    }
    func next() -> WeatherSnapshot {
        queue.isEmpty ? last : queue.removeFirst()
    }
}
