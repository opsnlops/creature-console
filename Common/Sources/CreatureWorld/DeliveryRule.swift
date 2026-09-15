import Foundation
import WorldCore

/// The founding moment, as a world rule over orders rather than a special case: an `order:*`
/// the Bridge says is out for delivery is `house · delivery.expected = "<items> (<carrier>),
/// today"` until midnight; one delivered is `delivery.arrived` for six hours. The truck in the
/// driveway is a happening, the delivery is a fact, and the mind puts them together - "April,
/// the robot parts are here!" - with no line written for it anywhere.
actor DeliveryRule {
    static let sourceID = try! SourceID(validating: "world:orders")
    static let arrivedFor: TimeInterval = 6 * 3_600

    let house: EntityID
    private let facts: FactRepository
    private let zone: TimeZone
    private let accept: @Sendable (WorldEventEnvelope) async throws -> Void
    /// What was cast per order and status, so each is said once.
    private var cast: Set<String> = []

    init(
        house: EntityID, facts: FactRepository, zone: TimeZone,
        accept: @escaping @Sendable (WorldEventEnvelope) async throws -> Void
    ) {
        self.house = house
        self.facts = facts
        self.zone = zone
        self.accept = accept
    }

    /// One pass over the orders. Returns the deliveries in force, by order.
    @discardableResult
    func sweep(now: Date) async throws -> [EntityID: String] {
        let statuses = try await facts.currentFacts(
            about: [], predicate: "order.status", limit: 500, at: now)
        var inForce: [EntityID: String] = [:]
        for status in statuses {
            guard case .string(let state) = status.value,
                state == "out_for_delivery" || state == "delivered"
            else { continue }
            let order = try await facts.currentFacts(subjectID: status.subjectID, at: now)
            let text = { (predicate: String) -> String? in
                if case .string(let value)? = order.first(where: { $0.predicate == predicate })?
                    .value
                {
                    return value
                }
                return nil
            }
            // Fresh means the mail said so lately - not that the Bridge cast it lately: a
            // June delivery read back in September is not at the door.
            let spoken = text("order.updated_at").flatMap(WorldJSON.date(from:)) ?? status.validFrom
            guard spoken > now.addingTimeInterval(-2 * 86_400) else { continue }
            var items: [String] = []
            if case .array(let values)? = order.first(where: { $0.predicate == "order.items" })?
                .value
            {
                items = values.compactMap { if case .string(let s) = $0 { s } else { nil } }
            }
            let what =
                items.isEmpty
                ? "an order from \(text("order.merchant") ?? "somewhere")"
                : items.joined(separator: ", ")
            let carrier = text("order.carrier").map { " (\($0))" } ?? ""
            let key = "\(status.subjectID.rawValue):\(state)"
            let predicate: String
            let value: String
            let until: Date
            if state == "out_for_delivery" {
                predicate = "delivery.expected"
                value = "\(what)\(carrier), today"
                until = endOfDay(now)
            } else {
                predicate = "delivery.arrived"
                value = "\(what)\(carrier)"
                until = now.addingTimeInterval(Self.arrivedFor)
            }
            inForce[status.subjectID] = value
            guard !cast.contains(key) else { continue }
            try await accept(
                try WorldEventEnvelope(
                    type: GivenFactAnnouncement.eventType,
                    occurredAt: now,
                    source: EventSource(id: Self.sourceID, kind: "world", sourceEventID: key),
                    subjectIDs: [house, status.subjectID],
                    epistemic: EpistemicState(type: .reported, confidence: 1),
                    payload: [
                        "subject_id": .string(house.rawValue),
                        "predicate": .string(predicate),
                        "value": .string(value),
                        "valid_to": .string(WorldJSON.timestamp(until)),
                        "order_id": .string(status.subjectID.rawValue),
                    ]))
            cast.insert(key)
        }
        return inForce
    }

    private func endOfDay(_ now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    }

    static let meanings: [String: String] = [
        "delivery.expected":
            "a package on its way to the house today: what it is and who is bringing it",
        "delivery.arrived":
            "a package the carrier says it delivered to the house, in the last few hours",
    ]
}
