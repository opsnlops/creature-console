import Foundation
import WorldCore

/// One text message, as plain values: the row, who, when, the words. Read from Messages'
/// database and forgotten as soon as it has been read; never written down, never cast.
struct TextMessage: Equatable, Sendable {
    /// `message.ROWID`: the checkpoint, and the provenance of whatever the message becomes.
    var rowID: Int64
    /// The other side's handle as Messages has it: a phone number or an email address.
    var handle: String
    var isFromMe: Bool
    var date: Date
    var text: String
    var chatIdentifier: String
    var isGroupChat: Bool
}

/// What a message from someone April knows turned out to be, in the Bridge's words - the
/// value is the fact, the row is the provenance, the words of the text stay on the Mac.
struct MessageTold: Equatable, Sendable, Codable {
    enum Kind: String, Codable, Sendable {
        /// Coming over, or on the way: `visitor.expected` on the person.
        case visit
        /// Asked April for something: `person.asked_april`.
        case request
        /// Something about themselves April would want the birds to know: `person.news`.
        case news
        /// A carrier's "left at the front door": `delivery.arrived` on the house.
        case delivery
    }

    var rowID: Int64
    var person: EntityID
    var kind: Kind
    var what: String
    var when: String
    var said: Date
    var until: Date

    var item: String { "message:\(rowID)" }
}

enum MessageFacts {
    static let visitFor: TimeInterval = 2 * 3_600
    static let requestFor: TimeInterval = 24 * 3_600
    static let newsFor: TimeInterval = 7 * 86_400
    static let deliveryFor: TimeInterval = 6 * 3_600

    static let meanings: [String: String] = [
        "person.asked_april":
            "something the person asked April for, by text, and when; a bird may remind her, or not",
        "person.news":
            "something the person told April about themselves, by text, and when they said it",
    ]

    /// How long a reading holds. A visit holds two hours, or until three hours past the time
    /// the text names ("there by 6" holds until 9); a request a day; news a week; a delivery
    /// the same few hours as the mail's rule.
    static func until(_ kind: MessageTold.Kind, when: String, said: Date, zone: TimeZone)
        -> Date
    {
        switch kind {
        case .visit:
            if let named = namedTime(in: when, after: said, zone: zone) {
                return named.addingTimeInterval(3 * 3_600)
            }
            return said.addingTimeInterval(visitFor)
        case .request: return said.addingTimeInterval(requestFor)
        case .news: return said.addingTimeInterval(newsFor)
        case .delivery: return said.addingTimeInterval(deliveryFor)
        }
    }

    /// "6", "6:30", "around 6pm", "at 18:00": the next such time after the text was sent.
    static func namedTime(in text: String, after said: Date, zone: TimeZone) -> Date? {
        let pattern = #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
            let hourRange = Range(match.range(at: 1), in: text),
            var hour = Int(text[hourRange]), (0...23).contains(hour)
        else { return nil }
        var minute = 0
        if let minuteRange = Range(match.range(at: 2), in: text) {
            minute = Int(text[minuteRange]) ?? 0
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let meridian = Range(match.range(at: 3), in: text).map {
            text[$0].lowercased().filter(\.isLetter)
        }
        if let meridian {
            if meridian == "pm", hour < 12 { hour += 12 }
            if meridian == "am", hour == 12 { hour = 0 }
        } else if hour <= 11 {
            // "there by 6" said in the afternoon means six this evening.
            let saidHour = calendar.component(.hour, from: said)
            if saidHour >= hour { hour += 12 }
        }
        guard hour <= 23 else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: said)
        components.hour = hour
        components.minute = minute
        guard let candidate = calendar.date(from: components) else { return nil }
        return candidate >= said
            ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate)
    }

    /// "at 1:40 PM" / "on Tuesday at 1:40 PM" - when the text came, beside the fact, so a
    /// bird knows how fresh the word is.
    static func saidClause(_ said: Date, now: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat =
            calendar.isDate(said, inSameDayAs: now) ? "h:mm a" : "EEEE 'at' h:mm a"
        return "texted \(formatter.string(from: said))"
    }

    /// The facts one reading makes.
    static func wanted(_ told: MessageTold, house: EntityID, now: Date, zone: TimeZone)
        -> FactLedger.Wanted
    {
        let said = saidClause(told.said, now: now, zone: zone)
        let when = told.when.isEmpty ? "" : ", \(told.when)"
        switch told.kind {
        case .visit:
            return FactLedger.Wanted(
                entityID: told.person,
                facts: ["visitor.expected": .string("\(told.what)\(when) (\(said))")],
                validUntil: told.until)
        case .request:
            return FactLedger.Wanted(
                entityID: told.person,
                facts: ["person.asked_april": .string("\(told.what)\(when) (\(said))")],
                validUntil: told.until)
        case .news:
            return FactLedger.Wanted(
                entityID: told.person,
                facts: ["person.news": .string("\(told.what) (\(said))")],
                validUntil: told.until)
        case .delivery:
            return FactLedger.Wanted(
                entityID: house,
                facts: ["delivery.arrived": .string("\(told.what) (\(said))")],
                validUntil: told.until)
        }
    }
}

extension PersonResolver {
    /// A Messages handle is a phone number or an email; the card has both.
    func person(handle: String) -> EntityID? {
        if handle.contains("@") { return person(email: handle, name: nil) }
        return person(phone: handle)
    }

    /// Phone numbers compare by their last ten digits: "(360) 555-0100" is "+13605550100".
    static func phoneKey(_ text: String) -> String {
        let digits = text.filter(\.isNumber)
        return String(digits.suffix(10))
    }
}
