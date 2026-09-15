import Foundation
import WorldCore

/// One mail message as the Bridge sees it: headers and the plain text of the body. The raw
/// message stays in Mail; this is what the extension hands over, and it is read, distilled,
/// and forgotten. Nothing of it is ever cast except the facts it makes.
struct MailMessage: Equatable, Sendable, Codable {
    var identifier: String
    var from: String
    var subject: String
    var date: Date
    var text: String
}

/// What kind of mail this is, decided cheaply before any model reads it. Only the first four
/// reach extraction; the rest are forgotten at once.
enum MailKind: String, Equatable, Sendable, Codable {
    case order, shipping, appointment, receipt, irrelevant
}

/// Cheap, deterministic classification on sender and subject: the merchants and carriers April
/// buys from and ships with, and the words their mail uses. Everything else is irrelevant and
/// never read further.
struct MailClassifier: Sendable {
    var carriers: [String]
    var merchants: [String]

    static let defaultCarriers = ["ups.com", "fedex.com", "usps.com", "dhl.com", "ontrac.com"]
    static let defaultMerchants = [
        "amazon.com", "adafruit.com", "digikey.com", "mouser.com", "sparkfun.com", "prusa3d.com",
        "mcmaster.com", "pololu.com", "servocity.com", "etsy.com", "ebay.com",
    ]

    init(carriers: [String] = defaultCarriers, merchants: [String] = defaultMerchants) {
        self.carriers = carriers.map { $0.lowercased() }
        self.merchants = merchants.map { $0.lowercased() }
    }

    func classify(_ message: MailMessage) -> MailKind {
        let from = message.from.lowercased()
        let subject = message.subject.lowercased()
        let known = carriers + merchants
        guard known.contains(where: { from.contains($0) }) else {
            // Appointment confirmations come from anyone; the subject must say so plainly.
            if Self.appointmentWords.contains(where: { subject.contains($0) }) {
                return .appointment
            }
            return .irrelevant
        }
        // The daily digest of what is in the mailbox is not a shipment.
        if subject.contains("daily digest") || from.contains("informeddelivery") {
            return .irrelevant
        }
        if Self.shippingWords.contains(where: { subject.contains($0) }) { return .shipping }
        if Self.orderWords.contains(where: { subject.contains($0) }) { return .order }
        if Self.receiptWords.contains(where: { subject.contains($0) }) { return .receipt }
        if carriers.contains(where: { from.contains($0) }) { return .shipping }
        return .irrelevant
    }

    static let shippingWords = [
        "shipped", "on its way", "out for delivery", "delivered", "delivery", "tracking",
        "arriving", "in transit", "your package", "has arrived", "arrives",
    ]
    static let orderWords = [
        "order confirmation", "your order", "order of", "ordered:", "order #", "order number",
        "thanks for your order", "thank you for your order", "order placed",
        "we received your order", "order received",
    ]
    static let receiptWords = ["receipt", "invoice", "payment", "paid"]
    static let appointmentWords = [
        "appointment", "reservation confirmed", "your reservation", "booking confirmed",
        "is confirmed", "reminder: your",
    ]
}

/// What a shipment mail says about where a package is.
enum ShipmentStatus: String, Equatable, Sendable, Codable, CaseIterable {
    case placed, shipped
    case outForDelivery = "out_for_delivery"
    case delivered
}

/// What the deterministic reader could pull from a message: numbers, statuses, and the
/// merchant - the parts with a shape. Item names and windows are the model's job, later.
struct MailReading: Equatable, Sendable {
    var kind: MailKind
    var merchant: String?
    var carrier: String?
    var orderNumber: String?
    var tracking: String?
    var status: ShipmentStatus?
    /// Items as the subject names them ("Your order of Servo Kit ×4 has shipped").
    var items: [String]
    var total: String? = nil
    /// The delivery window in the mail's words, when the model read one.
    var expected: String? = nil
}

/// Regexes for the parts of commerce mail that have a shape: order numbers, tracking numbers,
/// the carrier from the sender, the status from the subject.
enum MailReader {
    static func read(_ message: MailMessage, kind: MailKind) -> MailReading {
        let subject = message.subject
        let text = subject + "\n" + message.text
        let merchant = merchant(of: message)
        let carrier = carrier(in: message)
        // A carrier's mail has no merchant order number in it worth trusting; the tracking
        // number is what joins it to the order. Amazon is both, and keeps its order numbers.
        let fromCarrier = merchant.map { Self.carrierNames.contains($0) } ?? false
        return MailReading(
            kind: kind,
            merchant: merchant,
            carrier: carrier,
            orderNumber: fromCarrier && merchant != "amazon"
                ? nil : first(of: orderNumberPatterns, in: text),
            tracking: first(of: trackingPatterns, in: text),
            status: status(in: subject),
            items: items(in: subject))
    }

    static let carrierNames: Set<String> = ["ups", "fedex", "usps", "dhl", "ontrac"]

    /// "adafruit" from orders@adafruit.com, "amazon" from ship-confirm@amazon.com.
    static func merchant(of message: MailMessage) -> String? {
        guard let at = message.from.lastIndex(of: "@") else { return nil }
        let domain = message.from[message.from.index(after: at)...]
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "> "))
        let parts = domain.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        // The registrable name: amazon from ship-confirm.amazon.com, adafruit from adafruit.com.
        let name = parts[parts.count - 2]
        return name.isEmpty ? nil : String(name)
    }

    static func carrier(in message: MailMessage) -> String? {
        let haystack = (message.from + " " + message.subject + " " + message.text.prefix(2_000))
            .lowercased()
        for (word, name) in [
            ("ups", "UPS"), ("fedex", "FedEx"), ("usps", "USPS"), ("dhl", "DHL"),
            ("ontrac", "OnTrac"), ("amazon logistics", "Amazon"),
        ] where haystack.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
            return name
        }
        return nil
    }

    static func status(in subject: String) -> ShipmentStatus? {
        let s = subject.lowercased()
        if s.contains("out for delivery") || s.contains("arriving today") { return .outForDelivery }
        if s.contains("delivered") || s.contains("has arrived") { return .delivered }
        if s.contains("shipped") || s.contains("on its way") || s.contains("in transit") {
            return .shipped
        }
        if s.contains("order") { return .placed }
        return nil
    }

    /// "Your order of Servo Kit ×4 has shipped" → ["Servo Kit ×4"]; Amazon's
    /// "Ordered: \"Item\"" and "Shipped: Item" forms too.
    static func items(in subject: String) -> [String] {
        let patterns = [
            #"(?i)your (?:amazon\.com )?order of (.+?) has (?:shipped|been delivered|arrived)"#,
            #"(?i)(?:ordered|shipped|delivered|arriving today):\s*\"?(.+?)\"?\s*$"#,
            #"(?i)your order of (.+?)$"#,
        ]
        for pattern in patterns {
            if let match = firstGroup(pattern, in: subject) {
                let item = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if !item.isEmpty { return [item] }
            }
        }
        return []
    }

    /// Order numbers: Amazon's 3-7-7 shape, or "order #1234567" / "Order Number: WH-20441" -
    /// a token after the word that is mostly digits, never a stray word from the body.
    static let orderNumberPatterns = [
        #"(?i)order[:\s]*#?[:\s]*(\d{3}-\d{7}-\d{7})"#,
        #"(?i)order\s*(?:number|no\.?|#|id)?[:\s#]*(\d{5,20})\b"#,
        #"(?i)order\s*(?:number|no\.?|#|id)[:\s#]*([A-Z]{1,4}-?\d{4,20})\b"#,
    ]
    static let trackingPatterns = [
        #"\b(1Z[0-9A-Z]{16})\b"#,  // UPS
        #"\b(\d{20,22})\b"#,  // USPS
        #"\b(\d{12}|\d{15})\b"#,  // FedEx
        #"(?i)tracking\s*(?:number|no\.?|#|id)?[:\s#]*((?=[A-Z0-9]*\d{6})[A-Z0-9]{8,30})\b"#,
    ]

    private static func first(of patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            if let value = firstGroup(pattern, in: text) { return value }
        }
        return nil
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
            let group = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[group])
    }
}
