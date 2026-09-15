import Foundation
import FoundationModels

/// What the on-device model reads out of a commerce mail: only the fields with a place in an
/// order. Guided generation into this shape - never prose, never a summary of the mail.
@Generable(description: "What an order or shipping email says, taken from the email only.")
struct CommerceReading: Equatable, Sendable {
    @Guide(description: "The merchant's name, e.g. Adafruit, Amazon, DigiKey. Empty if unclear.")
    var merchant: String
    @Guide(description: "The order number exactly as the email prints it, or empty.")
    var orderNumber: String
    @Guide(description: "The carrier's tracking number exactly as printed, or empty.")
    var trackingNumber: String
    @Guide(
        description:
            "The items ordered or shipped, one short name each as the email names them, with quantity if given (\"Servo kit ×4\"). Empty if the email does not name them."
    )
    var items: [String]
    @Guide(description: "The order total with currency as printed, or empty.")
    var total: String
    @Guide(
        description:
            "The delivery window in the email's own words (\"Tuesday, September 16\", \"by 8 PM today\"), or empty."
    )
    var expectedDelivery: String
}

/// Apple Intelligence, on this Mac: reads the body of a mail the classifier accepted and fills
/// what the regexes could not. Unavailable is a state, not a failure - the deterministic
/// reading stands on its own and the Mail row says the model is not there.
struct MailDistiller: Sendable {
    static let maximumCharacters = 6_000

    /// Nil, with the reason, when the model is not available on this Mac right now.
    static func unavailableReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason): return "Apple Intelligence is not available: \(reason)"
        }
    }

    /// The model's reading of one message, or nil when it is not available or would not answer.
    func read(_ message: MailMessage) async -> CommerceReading? {
        guard Self.unavailableReason() == nil else { return nil }
        let session = LanguageModelSession(
            instructions: """
                You read one email about an order or a shipment and report what it says, exactly as \
                it says it. Never guess: a field the email does not state is empty. Item names are \
                the product names the email uses, shortened to a few words each.
                """)
        let body = String(message.text.prefix(Self.maximumCharacters))
        let prompt = "From: \(message.from)\nSubject: \(message.subject)\n\n\(body)"
        do {
            return try await session.respond(to: prompt, generating: CommerceReading.self).content
        } catch {
            return nil
        }
    }
}

extension MailReading {
    /// The deterministic reading, with the model's answers filling the gaps - never overriding
    /// a number the regexes found in the text.
    func filled(with model: CommerceReading?) -> MailReading {
        guard let model else { return self }
        var reading = self
        if reading.merchant == nil, !model.merchant.isEmpty {
            reading.merchant = model.merchant.lowercased()
        }
        if reading.orderNumber == nil, !model.orderNumber.isEmpty {
            reading.orderNumber = model.orderNumber
        }
        if reading.tracking == nil, !model.trackingNumber.isEmpty {
            reading.tracking = model.trackingNumber
        }
        if reading.items.isEmpty {
            // "Shipment", "Package", "1 item": the model naming the mail, not the goods.
            reading.items = model.items.map(Self.tidy).filter {
                !$0.isEmpty && !Self.isPlaceholder($0)
            }
        }
        if reading.total == nil, !model.total.isEmpty { reading.total = model.total }
        if reading.expected == nil, !model.expectedDelivery.isEmpty {
            reading.expected = model.expectedDelivery
        }
        return reading
    }
}

extension MailReading {
    /// An item name as a bird could say it: no bidi marks, no trailing ellipsis, no
    /// `" and 1 more item` tail from Amazon's subject lines.
    static func tidy(_ item: String) -> String {
        var text = item.replacingOccurrences(
            of: "[\u{2066}-\u{2069}]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #""?\s*and \d+ more items?$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"\s*(\.\.\.|…)"?$"#, with: "", options: .regularExpression)
        // Quotes anywhere in what is left are the mail's, not the product's.
        text = text.replacingOccurrences(of: "[\"“”]", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "',"))
    }

    /// Words a model gives when the mail names no product: not an item.
    static func isPlaceholder(_ item: String) -> Bool {
        let lower = item.lowercased()
        let generic = [
            "shipment", "package", "parcel", "order", "your order", "delivery", "item", "items",
            "your package", "your shipment",
        ]
        if generic.contains(lower) { return true }
        // "1 Kitchen item", "2 items": Amazon's placeholders.
        return lower.range(of: #"^\d+\s+(\w+\s+)?items?$"#, options: .regularExpression) != nil
    }
}
