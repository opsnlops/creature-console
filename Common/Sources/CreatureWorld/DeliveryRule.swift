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

    /// How long a delivered order stays current, and how long a shipped or placed one does with
    /// no further word from the mail (#234; April chose three days and two weeks). After that
    /// the order is history: its `order.*` facts end, and stay on the record.
    static let deliveredFor: TimeInterval = 3 * 86_400
    static let quietFor: TimeInterval = 14 * 86_400
    /// The most orders settled in one pass, so a first sweep of a month's backlog is gentle.
    static let maximumSettledPerSweep = 100

    /// Ends the orders the mail has finished with: delivered three days ago, or shipped and
    /// silent for two weeks. The order on 2026-09-14 that had the birds expecting a June DJI
    /// mic "tomorrow" was a `shipped` from June, still current in September. Returns the
    /// orders settled.
    @discardableResult
    func settle(now: Date) async throws -> [EntityID] {
        let statuses = try await facts.currentFacts(
            about: [], predicate: "order.status", limit: 2_000, at: now)
        var settled: [EntityID] = []
        for status in statuses where status.subjectID.rawValue.hasPrefix("order:") {
            guard settled.count < Self.maximumSettledPerSweep,
                case .string(let state) = status.value
            else { continue }
            let order = try await facts.currentFacts(subjectID: status.subjectID, at: now)
            let updated = order.first { $0.predicate == "order.updated_at" }
            let spoken =
                (updated.flatMap { fact -> Date? in
                    if case .string(let raw) = fact.value { return WorldJSON.date(from: raw) }
                    return nil
                }) ?? status.validFrom
            let age = now.timeIntervalSince(spoken)
            let reason: String
            if state == "delivered" {
                guard age >= Self.deliveredFor else { continue }
                reason = "delivered more than three days ago"
            } else {
                guard age >= Self.quietFor else { continue }
                reason = "\(state), and no word from the mail in two weeks"
            }
            try await accept(
                try WorldEventEnvelope(
                    type: OrderReducer.settled,
                    occurredAt: now,
                    // Keyed by the status it settles: a later word from the mail is a new
                    // status, and settles again in its time.
                    source: EventSource(
                        id: Self.sourceID, kind: "world",
                        sourceEventID: "settled:\(status.factID.rawValue)"),
                    subjectIDs: [status.subjectID],
                    epistemic: EpistemicState(type: .observed, confidence: 1),
                    payload: [
                        "status": .string(state),
                        "last_heard": .string(WorldJSON.timestamp(spoken)),
                        "reason": .string(reason),
                    ]))
            settled.append(status.subjectID)
        }
        return settled
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

/// `order.settled` → every reported `order.*` fact on the order ends, and stays on the record
/// as what was (#234). Not a deletion: the Viewer and the tools can still say what happened.
struct OrderReducer: WorldReducer {
    static let settled = WorldEventType(rawValue: "order.settled")!
    static let prefix = "order."

    let eventTypes: Set<WorldEventType> = [Self.settled]

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        guard let order = event.subjectIDs.first else { return WorldReduction() }
        return WorldReduction(retractions: [
            FactRetraction(
                subjectID: order, predicatePrefix: Self.prefix, except: [],
                producer: FactProducer(kind: PresenceFacts.producerKind, id: "orders", version: "1")
            )
        ])
    }
}
