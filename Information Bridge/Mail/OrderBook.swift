import Foundation
import WorldCore

/// An order April placed, as the world will hold it: `order:<merchant>-<number>`, kept for
/// good. April: "I think we should use order numbers in the database and it's okay to store
/// those." A shipment mail with the order number updates the order; one with only a tracking
/// number becomes `order:<carrier>-<tracking>` until a later mail joins them.
struct Order: Equatable, Sendable, Codable {
    var merchant: String
    var number: String?
    var carrier: String?
    var tracking: String?
    var items: [String]
    var total: String?
    var placed: Date?
    var status: ShipmentStatus
    var expected: String?
    var lastMail: Date

    var entityID: EntityID {
        let key = (number ?? tracking ?? "unknown").lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let who = merchant.lowercased().filter { $0.isLetter || $0.isNumber }
        return EntityID(rawValue: "order:\(who)-\(key)")!
    }

    /// "robot parts (servo kit ×4)" or, with nothing better, "an order from Adafruit".
    var description: String {
        items.isEmpty ? "an order from \(merchant.capitalized)" : items.joined(separator: ", ")
    }
}

/// Every order the Bridge has seen, joined across mails, on this Mac.
struct OrderBook: Sendable, Codable {
    private(set) var orders: [String: Order] = [:]

    /// Folds one mail's reading into the book. Returns the order it touched, if any.
    @discardableResult
    mutating func apply(_ reading: MailReading, at date: Date) -> Order? {
        guard reading.kind == .order || reading.kind == .shipping,
            let merchant = reading.merchant ?? reading.carrier?.lowercased()
        else { return nil }
        let key: String
        if let number = reading.orderNumber,
            let existing = orders.keys.first(where: {
                orders[$0]?.number == number
            })
        {
            key = existing
        } else if let tracking = reading.tracking,
            let existing = orders.keys.first(where: {
                orders[$0]?.tracking == tracking
            })
        {
            key = existing
        } else if let number = reading.orderNumber {
            key = "\(merchant)-\(number)"
        } else if let tracking = reading.tracking {
            key = "\(reading.carrier?.lowercased() ?? merchant)-\(tracking)"
        } else {
            return nil
        }
        var order =
            orders[key]
            ?? Order(
                merchant: reading.merchant ?? merchant, items: [], status: .placed, lastMail: date)
        // A mail about an order April placed at a merchant names the merchant better than a
        // carrier's does; the carrier's tracking number is welcome either way.
        if let merchant = reading.merchant, reading.carrier?.lowercased() != merchant {
            order.merchant = merchant
        }
        if let number = reading.orderNumber, order.number == nil { order.number = number }
        if let tracking = reading.tracking { order.tracking = tracking }
        if let carrier = reading.carrier { order.carrier = carrier }
        if !reading.items.isEmpty, order.items.isEmpty { order.items = reading.items }
        if let status = reading.status, date >= order.lastMail || status.rank > order.status.rank {
            order.status = max(order.status, status, by: \.rank)
        }
        if let total = reading.total { order.total = OrderFacts.tidyTotal(total) }
        if let expected = reading.expected {
            order.expected = OrderFacts.resolveExpected(expected, mailedOn: date)
        }
        if order.placed == nil, reading.kind == .order { order.placed = date }
        order.lastMail = max(order.lastMail, date)
        orders[key] = order
        return order
    }

    /// What the world should hold for every order: the facts on `order:*`, kept for good.
    var wanted: [String: FactLedger.Wanted] {
        var result: [String: FactLedger.Wanted] = [:]
        for (key, order) in orders {
            var facts: [String: WorldJSONValue] = [
                "order.merchant": .string(order.merchant.capitalized),
                "order.status": .string(order.status.rawValue),
                "order.items": .array(order.items.map(WorldJSONValue.string)),
                "order.for": .string("person:april"),
            ]
            if let number = order.number { facts["order.number"] = .string(number) }
            if let tracking = order.tracking { facts["order.tracking"] = .string(tracking) }
            if let carrier = order.carrier { facts["order.carrier"] = .string(carrier) }
            if let total = order.total { facts["order.total"] = .string(total) }
            if let placed = order.placed {
                facts["order.placed"] = .string(OrderFacts.day(placed))
            }
            // When the mail last spoke of it - the world's rules judge freshness by this, not
            // by when the Bridge got round to casting it.
            facts["order.updated_at"] = .string(WorldJSON.timestamp(order.lastMail))
            // A window matters until the package is in hand; "arriving tomorrow" in June must
            // never reach a bird in September.
            if let expected = order.expected, order.status != .delivered {
                facts["order.expected"] = .string(expected)
            }
            facts["order.last_heard"] = .string(OrderFacts.day(order.lastMail))
            result[key] = FactLedger.Wanted(entityID: order.entityID, facts: facts, validUntil: nil)
        }
        return result
    }
}

extension ShipmentStatus {
    var rank: Int {
        switch self {
        case .placed: 0
        case .shipped: 1
        case .outForDelivery: 2
        case .delivered: 3
        }
    }
}

private func max<T>(_ a: T, _ b: T, by key: KeyPath<T, Int>) -> T {
    a[keyPath: key] >= b[keyPath: key] ? a : b
}

enum OrderFacts {
    static let meanings: [String: String] = [
        "order.merchant": "where April ordered from",
        "order.number": "the merchant's order number, as their mail gives it",
        "order.items": "what was ordered, as the mail names it",
        "order.status":
            "where the order was as of order.last_heard: placed, shipped, out_for_delivery, or delivered; a shipped order not heard of for weeks has almost surely arrived",
        "order.tracking": "the carrier's tracking number",
        "order.carrier": "who is carrying it",
        "order.total": "what the order cost, as the mail gives it",
        "order.placed": "the day the order was placed",
        "order.expected":
            "the day the carrier said it would arrive, as of order.last_heard; the mail rarely says when a package actually came, so a day long past is old news, not a delivery due",
        "order.last_heard":
            "the day the mail last spoke of the order - how old the news in order.status and order.expected is",
        "order.for": "whose order it is",
        "order.updated_at":
            "when the mail last spoke of the order, as a timestamp - for the world's rules",
    ]
    static let worldOnly: Set<String> = ["order.tracking", "order.updated_at"]

    /// "21.689999999999998 USD" → "$21.69"; anything the model gives as words stays as words.
    static func tidyTotal(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ")
        if parts.count == 2, let amount = Double(parts[0]), parts[1].uppercased() == "USD" {
            return String(format: "$%.2f", amount)
        }
        if let amount = Double(trimmed) { return String(format: "$%.2f", amount) }
        return trimmed
    }

    static func day(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }

    private static let monthNames = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september",
        "october", "november", "december",
    ]
    private static let weekdayNames = [
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    ]

    /// The carrier's window as a day, judged from the day the mail came: "Arriving tomorrow"
    /// on June 7 is June 8; "by Thursday" the Thursday after; "Monday, September 16" itself.
    /// Words the Bridge cannot place keep the mail's date beside them, so they never pass
    /// for news.
    static func resolveExpected(_ text: String, mailedOn mailed: Date, zone: TimeZone = .current)
        -> String
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.startOfDay(for: mailed)
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for (index, word) in words.enumerated() where word.count >= 3 {
            guard let month = monthNames.firstIndex(where: { $0.hasPrefix(word) }),
                index + 1 < words.count, let dayNumber = Int(words[index + 1]),
                (1...31).contains(dayNumber)
            else { continue }
            var components = calendar.dateComponents([.year], from: start)
            components.month = month + 1
            components.day = dayNumber
            guard let date = calendar.date(from: components) else { continue }
            // A day already gone when the mail came means next year's.
            let resolved = date < start ? calendar.date(byAdding: .year, value: 1, to: date)! : date
            return day(resolved, zone: zone)
        }
        if words.contains("today") { return day(start, zone: zone) }
        if words.contains("tomorrow") {
            return day(calendar.date(byAdding: .day, value: 1, to: start)!, zone: zone)
        }
        for (index, name) in weekdayNames.enumerated() where words.contains(name) {
            let today = calendar.component(.weekday, from: start) - 1
            let ahead = (index - today + 7) % 7
            let date = calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: start)!
            return day(date, zone: zone)
        }
        return
            "\(text.trimmingCharacters(in: .whitespacesAndNewlines)) (as of \(day(mailed, zone: zone)))"
    }
}
