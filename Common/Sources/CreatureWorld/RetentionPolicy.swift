import Foundation
import WorldCore

/// How long the world keeps its raw material. Everything here is bookkeeping that stops
/// mattering: the event log, percept snapshots, finished timers, superseded facts, old scenes.
/// The conversation is kept, and the memories the nightly job writes are kept for years — April:
/// "let's keep the fact summaries … for a very long time." Retention never touches a current
/// fact; only `valid_to` (set when a fact is superseded or expires) starts its clock.
struct RetentionPolicy: Codable, Equatable, Sendable {
    /// The event log. `cheapEvents` (measurements and the pacing timers, state not story) get
    /// `cheapEventDays`; everything else `eventDays`.
    var eventDays: Int
    var cheapEventDays: Int
    /// One bookkeeping row per event.
    var processingDays: Int
    /// Timers once fired or cancelled.
    var timerDays: Int
    /// An utterance with the percept it produced (the fat one); the words stay in the
    /// conversation.
    var ingressDays: Int
    /// A fact after it was superseded or expired.
    var retiredFactDays: Int
    /// Deliveries and stage decisions.
    var deliveryDays: Int
    /// Closed scenes.
    var sceneDays: Int

    init(
        eventDays: Int = 90, cheapEventDays: Int = 7, processingDays: Int = 7, timerDays: Int = 7,
        ingressDays: Int = 30, retiredFactDays: Int = 90, deliveryDays: Int = 90,
        sceneDays: Int = 180
    ) {
        self.eventDays = eventDays
        self.cheapEventDays = cheapEventDays
        self.processingDays = processingDays
        self.timerDays = timerDays
        self.ingressDays = ingressDays
        self.retiredFactDays = retiredFactDays
        self.deliveryDays = deliveryDays
        self.sceneDays = sceneDays
    }

    /// Events that are state rather than story: measurements every fifteen seconds, and the
    /// timers that pace the floor.
    static let cheapEvents: Set<WorldEventType> = [
        HouseEvents.measurementChanged, SceneService.floorReadyEventType,
        SceneService.floorExpiredEventType,
    ]

    func days(for eventType: WorldEventType) -> Int {
        Self.cheapEvents.contains(eventType) ? cheapEventDays : eventDays
    }

    /// When an event of this type, at this time, stops mattering.
    func expiry(for eventType: WorldEventType, occurredAt: Date) -> Date {
        occurredAt.addingTimeInterval(TimeInterval(days(for: eventType)) * 86_400)
    }

    private enum CodingKeys: String, CodingKey {
        case eventDays = "event_days"
        case cheapEventDays = "cheap_event_days"
        case processingDays = "processing_days"
        case timerDays = "timer_days"
        case ingressDays = "ingress_days"
        case retiredFactDays = "retired_fact_days"
        case deliveryDays = "delivery_days"
        case sceneDays = "scene_days"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RetentionPolicy()
        func days(_ key: CodingKeys, _ fallback: Int) throws -> Int {
            let value = try container.decodeIfPresent(Int.self, forKey: key) ?? fallback
            guard value >= 1 else {
                throw CreatureWorldConfigurationError.invalidRetention(key.rawValue)
            }
            return value
        }
        self.init(
            eventDays: try days(.eventDays, defaults.eventDays),
            cheapEventDays: try days(.cheapEventDays, defaults.cheapEventDays),
            processingDays: try days(.processingDays, defaults.processingDays),
            timerDays: try days(.timerDays, defaults.timerDays),
            ingressDays: try days(.ingressDays, defaults.ingressDays),
            retiredFactDays: try days(.retiredFactDays, defaults.retiredFactDays),
            deliveryDays: try days(.deliveryDays, defaults.deliveryDays),
            sceneDays: try days(.sceneDays, defaults.sceneDays))
    }
}
