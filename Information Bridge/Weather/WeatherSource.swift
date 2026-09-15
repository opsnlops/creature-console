import CoreLocation
import Foundation
import WeatherKit
import WorldCore

/// The state of one of the Bridge's sources, for the window.
struct SourceStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case off
        case on
        case degraded(String)
    }

    var state: State = .off
    var lastRunAt: Date?
    var note: String?
}

/// Step 2 of the plan: WeatherKit, for the house's sky. Polled hourly; every fact is cast only
/// when its value changes, with the item id carrying the moment, so the world sees each change
/// once and never a repeat. The house's rain gauge knows the past; this knows the next two days.
actor WeatherSource {
    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void
    typealias Fetch = @Sendable (CLLocation) async throws -> WeatherSnapshot

    static let interval: Duration = .seconds(3_600)
    static let sourceName = "weather"

    let place: EntityID
    let location: CLLocation
    let zone: TimeZone
    private let fetch: Fetch
    private let cast: Cast
    private let memory: URL
    private var lastCast: [String: WorldJSONValue] = [:]
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?

    init(
        place: EntityID, latitude: Double, longitude: Double, zone: TimeZone, directory: URL,
        fetch: @escaping Fetch = WeatherSource.fetchFromWeatherKit, cast: @escaping Cast
    ) {
        self.place = place
        self.location = CLLocation(latitude: latitude, longitude: longitude)
        self.zone = zone
        self.fetch = fetch
        self.cast = cast
        self.memory = directory.appending(path: "weather-last-cast.json")
        if let data = try? Data(contentsOf: memory),
            let saved = try? WorldJSON.makeDecoder().decode(
                [String: WorldJSONValue].self, from: data)
        {
            lastCast = saved
        }
    }

    func start() {
        guard worker == nil else { return }
        worker = Task {
            while !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        status.state = .off
        publish()
    }

    func updates() -> AsyncStream<SourceStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { _ in Task { await self.forget(id) } }
        }
    }

    private func forget(_ id: UUID) { observers[id] = nil }

    /// One reading of the sky, turned into facts, the changed ones cast.
    func poll(now: Date = Date()) async {
        do {
            let snapshot = try await fetch(location)
            let facts = WeatherFacts.facts(from: snapshot, now: now, zone: zone)
            var cast = 0
            for fact in facts where lastCast[fact.predicate] != fact.value {
                try await self.cast(
                    try BridgeFacts.given(
                        subject: place, predicate: fact.predicate, value: fact.value,
                        validUntil: fact.validUntil, source: Self.sourceName,
                        itemID: "\(fact.predicate):\(WorldJSON.timestamp(now))", at: now))
                lastCast[fact.predicate] = fact.value
                cast += 1
            }
            try? WorldJSON.makeEncoder().encode(lastCast).write(to: memory, options: .atomic)
            status = SourceStatus(
                state: .on, lastRunAt: now,
                note: cast == 0 ? "nothing changed" : "\(cast) fact\(cast == 1 ? "" : "s") changed")
        } catch {
            status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now, note: nil)
        }
        publish()
    }

    private func publish() {
        for observer in observers.values { observer.yield(status) }
    }

    /// WeatherKit, for real: the daily forecast, the next two days by the hour, and any alerts.
    static func fetchFromWeatherKit(_ location: CLLocation) async throws -> WeatherSnapshot {
        let (daily, hourly, alerts) = try await WeatherService.shared.weather(
            for: location, including: .daily, .hourly, .alerts)
        let days = daily.forecast.prefix(3).map { day in
            WeatherSnapshot.Day(
                date: day.date, condition: day.condition.description,
                highF: day.highTemperature.converted(to: .fahrenheit).value,
                lowF: day.lowTemperature.converted(to: .fahrenheit).value,
                rainChance: day.precipitationChance,
                rainInches: day.precipitationAmount.converted(to: .inches).value,
                sunrise: day.sun.sunrise, sunset: day.sun.sunset)
        }
        let hours = hourly.forecast.prefix(48).map { hour in
            WeatherSnapshot.Hour(
                date: hour.date, rainChance: hour.precipitationChance,
                condition: hour.condition.description)
        }
        let warnings = (alerts ?? []).map { alert in
            WeatherSnapshot.Alert(
                id: alert.detailsURL.absoluteString, summary: alert.summary,
                severity: alert.severity.description, expires: alert.metadata.expirationDate)
        }
        return WeatherSnapshot(days: Array(days), hours: Array(hours), alerts: warnings)
    }
}
