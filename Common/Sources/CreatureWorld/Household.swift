import Foundation
import WorldCore

/// Who is about, as the house knows it, the moment a camera sees someone: April's presence
/// from the sensor, and whoever is expected. April lives alone; the stage note carries this so
/// the minds never guess at a shape. Read afresh for every occasion - a scene's note is about
/// now.
enum Household {
    static let april = try! EntityID(validating: "person:april")

    static func situation(facts: FactRepository, at now: Date, zone: TimeZone) async throws
        -> HouseholdSituation
    {
        // Orders that could be at the door today: those the mail expects today, and those out
        // for delivery. Each is read whole only when it is one of these.
        let dueToday = try await facts.currentFacts(
            about: [], predicate: WorldFacts.orderExpected, limit: 500, at: now
        ).filter { expectedToday($0, now: now, zone: zone) }
        let outForDelivery = try await facts.currentFacts(
            about: [], predicate: WorldFacts.orderStatus, limit: 500, at: now
        ).filter { $0.value == .string("out_for_delivery") }
        var orders: [[Fact]] = []
        for subject in Set((dueToday + outForDelivery).map(\.subjectID)).sorted(by: {
            $0.rawValue < $1.rawValue
        }) {
            orders.append(try await facts.currentFacts(subjectID: subject, at: now))
        }
        return situation(
            aprilFacts: try await facts.currentFacts(subjectID: april, at: now),
            expected: try await facts.currentFacts(
                subjectID: nil, predicatePrefix: WorldFacts.visitorExpected, after: nil, limit: 5,
                at: now),
            orders: orders, now: now, zone: zone)
    }

    /// `presence.state` on April, every `visitor.expected` in force - on the house, or on
    /// the person coming (the calendar's rule casts it there) - and each order's facts, whole.
    static func situation(
        aprilFacts: [Fact], expected: [Fact], orders: [[Fact]] = [], now: Date = Date(),
        zone: TimeZone = .current
    ) -> HouseholdSituation {
        let home: Bool?
        if case .string(let state)? = aprilFacts.first(where: {
            $0.predicate == WorldFacts.personState
        })?.value {
            home = state == PersonPresenceState.home.rawValue
        } else {
            home = nil
        }
        let visitors = expected.compactMap { fact -> String? in
            guard case .string(let words) = fact.value, !words.isEmpty else { return nil }
            if fact.subjectID.rawValue.hasPrefix("person:") {
                return "\(SceneOpeningPolicy.placeName(fact.subjectID)), \(words)"
            }
            return words
        }
        let deliveries = orders.compactMap { delivery(of: $0, now: now, zone: zone) }
        return HouseholdSituation(
            aprilHome: home,
            visitorExpected: visitors.isEmpty ? nil : visitors.joined(separator: "; "),
            deliveryExpected: deliveries.isEmpty ? nil : deliveries.joined(separator: "; "))
    }

    /// "Amazon: Hardware" for an order that could be at the door today: not yet delivered,
    /// and either expected today or out for delivery since this morning. On 2026-09-25 the
    /// Amazon driver was called April - the order went shipped to delivered with no "out for
    /// delivery" mail between, and the house counted only invited visitors.
    static func delivery(of order: [Fact], now: Date, zone: TimeZone) -> String? {
        let text = { (predicate: String) -> String? in
            if case .string(let value)? = order.first(where: { $0.predicate == predicate })?.value {
                return value
            }
            return nil
        }
        let status = text(WorldFacts.orderStatus)
        guard status != "delivered" else { return nil }
        let expected = order.first { $0.predicate == WorldFacts.orderExpected }
        let outToday =
            status == "out_for_delivery"
            && (text("order.updated_at").flatMap(WorldJSON.date(from:))
                ?? order.first { $0.predicate == WorldFacts.orderStatus }?.validFrom).map {
                    calendar(zone).isDate($0, inSameDayAs: now)
                } == true
        guard outToday || expected.map({ expectedToday($0, now: now, zone: zone) }) == true
        else { return nil }
        var items: [String] = []
        if case .array(let values)? = order.first(where: { $0.predicate == "order.items" })?.value {
            items = values.compactMap { if case .string(let s) = $0 { s } else { nil } }
        }
        let merchant = text("order.merchant") ?? "an order"
        return items.isEmpty ? merchant : "\(merchant): \(items.joined(separator: ", "))"
    }

    /// Whether an `order.expected` names today. The Bridge resolves every expectation to one
    /// day, worded "September 25, 2026" in the house's zone.
    static func expectedToday(_ fact: Fact, now: Date, zone: TimeZone) -> Bool {
        guard case .string(let words) = fact.value else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "MMMM d, yyyy"
        return words.hasPrefix(formatter.string(from: now))
    }

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static let sourceID = try! SourceID(validating: "world:household")
    /// How long the house's word on a sighting stands: long enough to cover the visit to the
    /// kitchen, short enough that a real visitor an hour later is not called April.
    static let identificationLifetime: TimeInterval = 30 * 60

    /// The house's own word on who a camera saw, as a fact: `sighting.identified = April` on
    /// the place, when she is home and nobody is expected. The stage note says it to the
    /// birds in the moment (#200); this writes it into the record, so the day's story, the
    /// Viewer, and a question an hour later agree with what was said. Nil when the house
    /// cannot say.
    static func identification(
        of event: WorldEventEnvelope, place: EntityID, situation: HouseholdSituation, now: Date
    ) throws -> WorldEventEnvelope? {
        guard event.type == HouseEvents.personSeen, situation.aprilHome == true,
            situation.nobodyExpected
        else { return nil }
        return try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType,
            occurredAt: now,
            source: EventSource(
                id: sourceID, kind: "world", sourceEventID: "identified:\(event.eventID.rawValue)"),
            subjectIDs: [place, april],
            placeID: place,
            epistemic: EpistemicState(type: .assumed, confidence: 0.95),
            payload: [
                "subject_id": .string(place.rawValue),
                "predicate": .string(WorldFacts.sightingIdentified),
                "value": .string("April"),
                "valid_for_seconds": .number(identificationLifetime),
            ],
            causedBy: [.event(event.eventID)])
    }
}
