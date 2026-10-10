import Foundation
import WorldCore

/// The daylight's arithmetic, apart from the store: given the light readings as they come, which
/// way the light is going, and whether this one is dusk or dawn. One reading tells the birds what
/// the sky is doing now; Mango's point (2026-10-10) was that nightfall is a trend - "a threshold
/// plus a falling trend would catch dusk before it gets properly dark" (#223).
struct DaylightTracker: Sendable {
    struct Reading: Equatable, Sendable {
        var lux: Double
        var at: Date
    }

    enum Trend: String, Equatable, Sendable {
        case brightening, steady, dimming
    }

    enum Moment: Equatable, Sendable {
        case dusk, dawn
    }

    struct Outcome: Equatable, Sendable {
        var trend: Trend?
        var moment: Moment?
    }

    /// Where dusk and dawn are drawn: the middle of the dusk band - an overcast sunset, or a
    /// clear one ten or fifteen minutes on. Civil dusk ends near 3 lux.
    static let threshold: Double = 100
    /// The trend compares the newest reading with the oldest from this long before it...
    static let window: TimeInterval = 30 * 60
    /// ...or, when none is that recent, with the last reading at all if it is no older than this.
    static let fallback: TimeInterval = 60 * 60
    /// How long a trend holds unless a reading renews it: when the readings stop - all night,
    /// at 0 lux - the trend lapses rather than saying "dimming" until morning.
    static let trendLifetime: TimeInterval = 45 * 60

    let zone: TimeZone
    private(set) var readings: [Reading]
    /// The local day of the last dusk and dawn: each is a moment once a day, whatever the
    /// clouds do around the line.
    private var duskDay: String?
    private var dawnDay: String?

    init(zone: TimeZone, seed: Reading? = nil) {
        self.zone = zone
        self.readings = seed.map { [$0] } ?? []
    }

    mutating func observe(_ reading: Reading) -> Outcome {
        let earlier = readings.filter { $0.at < reading.at }
        let baseline =
            earlier.first { reading.at.timeIntervalSince($0.at) <= Self.window }
            ?? earlier.last.flatMap {
                reading.at.timeIntervalSince($0.at) <= Self.fallback ? $0 : nil
            }
        var outcome = Outcome(trend: baseline.map { Self.trend(from: $0.lux, to: reading.lux) })

        if let previous = earlier.last {
            let day = Self.day(of: reading.at, in: zone)
            let afternoon = Self.hour(of: reading.at, in: zone) >= 12
            // The noon line keeps a dark storm from passing for dusk, and a storm clearing
            // in the afternoon from passing for dawn.
            if afternoon, previous.lux >= Self.threshold, reading.lux < Self.threshold,
                duskDay != day
            {
                outcome.moment = .dusk
                duskDay = day
            } else if !afternoon, previous.lux < Self.threshold,
                reading.lux >= Self.threshold, dawnDay != day
            {
                outcome.moment = .dawn
                dawnDay = day
            }
        }

        readings = (earlier + [reading]).filter {
            reading.at.timeIntervalSince($0.at) <= Self.fallback
        }
        return outcome
    }

    /// Light spans orders of magnitude, so the trend is a ratio; the one lux added to each side
    /// keeps a night of zeros from dividing by nothing.
    static func trend(from old: Double, to new: Double) -> Trend {
        let ratio = (new + 1) / (old + 1)
        if ratio <= 0.6 { return .dimming }
        if ratio >= 1.6 { return .brightening }
        return .steady
    }

    static func day(of date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func hour(of date: Date, in zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.component(.hour, from: date)
    }
}

/// The daylight as a world rule: every light reading the house tells the world renews the
/// trend (`environment.light_trend`), and the reading that crosses the line is dusk or dawn -
/// a happening, and, by `consider_on`, the house's occasion for the birds to notice nightfall.
actor DaylightRule {
    static let sourceID = try! SourceID(validating: "world:daylight")
    /// The house's measurement this rule reads, and the one it writes beside it.
    static let lightPredicate = "light_lux"
    static let trendPredicate = "light_trend"

    private let zone: TimeZone
    private let facts: FactRepository
    private let accept: @Sendable (WorldEventEnvelope) async throws -> Void
    private var trackers: [EntityID: DaylightTracker] = [:]

    init(
        zone: TimeZone, facts: FactRepository,
        accept: @escaping @Sendable (WorldEventEnvelope) async throws -> Void
    ) {
        self.zone = zone
        self.facts = facts
        self.accept = accept
    }

    /// At startup: the light the world already knows is the reading the next one is weighed
    /// against, so a dusk that falls just after a restart is still seen crossing the line.
    func seed(now: Date) async throws {
        let light = try await facts.currentFacts(
            about: [], predicate: WorldFacts.environmentPrefix + Self.lightPredicate, limit: 50,
            at: now)
        for fact in light {
            guard case .number(let lux) = fact.value else { continue }
            trackers[fact.subjectID] = DaylightTracker(
                zone: zone, seed: DaylightTracker.Reading(lux: lux, at: fact.validFrom))
        }
    }

    /// An event from the world's stream; anything but a light reading is ignored.
    func heard(_ event: WorldEventEnvelope) async throws {
        guard event.type == HouseEvents.measurementChanged,
            case .string(Self.lightPredicate)? = event.payload["predicate"],
            case .number(let lux)? = event.payload["value"],
            let place = event.subjectIDs.first
        else { return }
        var tracker = trackers[place] ?? DaylightTracker(zone: zone)
        let outcome = tracker.observe(DaylightTracker.Reading(lux: lux, at: event.occurredAt))
        trackers[place] = tracker
        let stamp = WorldJSON.timestamp(event.occurredAt)
        if let trend = outcome.trend {
            try await accept(
                try WorldEventEnvelope(
                    type: HouseEvents.measurementChanged,
                    occurredAt: event.occurredAt,
                    source: EventSource(
                        id: Self.sourceID, kind: "world",
                        sourceEventID: "\(Self.trendPredicate):\(place.rawValue):\(stamp)"),
                    subjectIDs: [place],
                    epistemic: EpistemicState(type: .inferred, confidence: 1),
                    payload: [
                        "predicate": .string(Self.trendPredicate),
                        "value": .string(trend.rawValue),
                        "valid_for_seconds": .number(DaylightTracker.trendLifetime),
                    ],
                    causedBy: [.event(event.eventID)],
                    trace: event.trace))
        }
        if let moment = outcome.moment {
            let type = moment == .dusk ? HouseEvents.dusk : HouseEvents.dawn
            try await accept(
                try WorldEventEnvelope(
                    type: type,
                    occurredAt: event.occurredAt,
                    source: EventSource(
                        id: Self.sourceID, kind: "world",
                        sourceEventID:
                            "\(type.rawValue):\(place.rawValue):\(DaylightTracker.day(of: event.occurredAt, in: zone))"
                    ),
                    subjectIDs: [place],
                    placeID: place,
                    epistemic: EpistemicState(type: .inferred, confidence: 1),
                    payload: ["lux": .number(lux)],
                    causedBy: [.event(event.eventID)],
                    trace: event.trace))
        }
    }
}
