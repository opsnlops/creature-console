import Foundation
import FoundationModels
import WorldCore

/// What the on-device model reads out of an appointment mail: who is coming (or where April
/// is going), for what, on which day and at what time, in the mail's own words. The date and
/// time are resolved deterministically afterwards; the model only copies.
@Generable(
    description:
        "What an appointment confirmation or reminder email says, taken from the email only.")
struct AppointmentReading: Equatable, Sendable {
    @Guide(
        description:
            "The business or person the appointment is with, as the email names them. Empty if unclear."
    )
    var business: String
    @Guide(
        description: "What the appointment is for, in a few words. Empty if the email does not say."
    )
    var service: String
    @Guide(
        description:
            "The date of the appointment, copied exactly as the email writes it. Empty if the email gives none."
    )
    var dateWords: String
    @Guide(
        description:
            "The time or time window of the appointment, copied exactly as the email writes it. Empty if the email gives none."
    )
    var timeWords: String
    @Guide(
        description:
            "True when the provider comes to April's home - the email gives her address, or April's own words in the thread say they come to her house; false when April goes to them or nothing says."
    )
    var atAprilsHome: Bool
    @Guide(description: "True only when the email cancels the appointment.")
    var isCancellation: Bool
}

/// One question, asked on its own when the reading did not settle it: where does the
/// appointment happen? The quote is the guard - "at April's house" stands only on words that
/// are in the thread.
@Generable(description: "Where the appointment takes place.")
struct PlaceReading: Equatable, Sendable {
    @Guide(
        description:
            "True when the appointment happens at April's house - the sender or their crew will arrive there - even if April herself will be out. False when April goes somewhere for it, or nothing says."
    )
    var atAprilsHouse: Bool
    @Guide(
        description:
            "The exact words, copied character for character, that show the sender or crew arriving at April's house (or April going elsewhere). Empty when nothing says."
    )
    var quote: String
}

/// Apple Intelligence reads the appointment mail; the date words it copies must be in the
/// mail, or the reading is refused - a small model will otherwise invent a Tuesday.
struct AppointmentDistiller: Sendable {
    func read(_ message: MailMessage) async -> AppointmentReading? {
        guard MailDistiller.unavailableReason() == nil else { return nil }
        let session = LanguageModelSession(
            instructions: """
                You read one email about an appointment and report what it says, copying dates \
                and times exactly as written. The subject line counts. A reply may quote what \
                April wrote earlier; her words are true and may say where and when, but the \
                appointment is the sender's visit, not anything April is doing elsewhere. \
                Never guess: a field the email does not state is empty. Never repeat anything \
                from these instructions.
                """)
        let prompt = Self.prompt(for: message)
        do {
            var reading = try await session.respond(to: prompt, generating: AppointmentReading.self)
                .content
            guard Self.isSupported(reading, by: message) else { return nil }
            if !reading.atAprilsHome, await comesToAprilsHome(prompt: prompt, message: message) {
                reading.atAprilsHome = true
            }
            return reading
        } catch {
            return nil
        }
    }

    /// The place, asked on its own: a small model reading everything at once misses "when
    /// the crew arrives", but answers the one question, and must quote its evidence.
    private func comesToAprilsHome(prompt: String, message: MailMessage) async -> Bool {
        let session = LanguageModelSession(
            instructions: """
                You answer one question about an email thread: where does the appointment \
                take place - at April's house, with the sender or their crew arriving there, or \
                somewhere April goes? Whether April herself will be in does not matter; a crew \
                arriving at her house while she is out is still at her house. April's own \
                quoted words count. Decide only on words in the thread, and copy them exactly.
                """)
        let answer = try? await session.respond(to: prompt, generating: PlaceReading.self).content
        IMAPIntake.log.notice(
            "Mail: at April's house? \(answer?.atAprilsHouse == true ? "yes" : "no", privacy: .public) - \"\(answer?.quote ?? "", privacy: .private)\""
        )
        guard let place = answer, place.atAprilsHouse else { return false }
        let (latest, quoted) = MailText.parts(of: message.text)
        let quote = Self.squeeze(place.quote)
        // The words must be in the thread, and be about the house: "on the mainland" is a
        // place, but not this one.
        let aboutTheHouse = Self.houseWords.contains { place.quote.lowercased().contains($0) }
        return quote.count >= 6 && aboutTheHouse
            && Self.squeeze(message.subject + " " + latest + " " + quoted).contains(quote)
    }

    static let houseWords = [
        "home", "house", "door", "address", "arrive", "crew", "come by", "come over", "stop by",
        "your place", "be there", "on site", "on-site", "driveway", "gate",
    ]

    /// The mail as the model sees it: the subject, the sender's latest words, then what they
    /// quoted - April's earlier message, most often - marked as such.
    static func prompt(for message: MailMessage) -> String {
        let (latest, quoted) = MailText.parts(of: message.text)
        let sender = MailReader.displayName(of: message.from)
        var prompt = "Subject: \(message.subject)\n\nThe latest message, from \(sender):\n"
        prompt += String(latest.prefix(MailDistiller.maximumCharacters))
        if !quoted.isEmpty {
            prompt += "\n\nQuoted below it, written earlier by April:\n"
            prompt += String(quoted.prefix(MailDistiller.maximumCharacters / 2))
        }
        return prompt
    }

    static func isSupported(_ reading: AppointmentReading, by message: MailMessage) -> Bool {
        // The attribution line's date is nobody's appointment: only the subject and the
        // words of the thread count.
        let (latest, quoted) = MailText.parts(of: message.text)
        let mail = squeeze(message.subject + " " + latest + " " + quoted)
        let date = squeeze(reading.dateWords)
        guard date.count >= 3, mail.contains(date) else { return false }
        let time = squeeze(reading.timeWords)
        return time.isEmpty || mail.contains(time)
    }

    private static func squeeze(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Days and clock times as mail writes them, resolved against the day the mail came.
enum MailDates {
    private static let monthNames = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september",
        "october", "november", "december",
    ]
    private static let weekdayNames = [
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    ]

    /// "Thursday, September 18", "Sep 18", "9/18", "tomorrow", "Thursday": the day, judged from
    /// the day the mail came (a day already gone is next year's or next week's).
    static func day(in text: String, mailedOn mailed: Date, zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.startOfDay(for: mailed)
        let lower = text.lowercased()
        // "17th" is 17; "1st", "2nd", "3rd" likewise.
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .map { word -> String in
                if let match = word.wholeMatch(of: /(\d{1,2})(st|nd|rd|th)/) {
                    return String(match.1)
                }
                return word
            }
        for (index, word) in words.enumerated() where word.count >= 3 {
            guard let month = monthNames.firstIndex(where: { $0.hasPrefix(word) }),
                index + 1 < words.count, let dayNumber = Int(words[index + 1]),
                (1...31).contains(dayNumber)
            else { continue }
            var year = calendar.component(.year, from: start)
            if index + 2 < words.count, let given = Int(words[index + 2]), given > 2000 {
                year = given
            }
            var components = DateComponents()
            components.year = year
            components.month = month + 1
            components.day = dayNumber
            guard let date = calendar.date(from: components) else { continue }
            if date < start, year == calendar.component(.year, from: start) {
                return calendar.date(byAdding: .year, value: 1, to: date)
            }
            return date
        }
        // 9/18 or 9/18/2026.
        if let match = lower.firstMatch(of: /\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/),
            let month = Int(match.1), let dayNumber = Int(match.2), (1...12).contains(month),
            (1...31).contains(dayNumber)
        {
            var components = DateComponents()
            components.year =
                match.3.flatMap { Int($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
                ?? calendar.component(.year, from: start)
            components.month = month
            components.day = dayNumber
            if let date = calendar.date(from: components) {
                return date < start && match.3 == nil
                    ? calendar.date(byAdding: .year, value: 1, to: date) : date
            }
        }
        if words.contains("today") { return start }
        if words.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: start) }
        // A reminder that names today's weekday means today.
        for (index, name) in weekdayNames.enumerated() where words.contains(name) {
            let today = calendar.component(.weekday, from: start) - 1
            return calendar.date(byAdding: .day, value: (index - today + 7) % 7, to: start)
        }
        // "the 16th", no month: an appointment is ahead, so the next 16th there is.
        if let ordinal = lower.firstMatch(of: /\b(\d{1,2})(?:st|nd|rd|th)\b/),
            let dayNumber = Int(ordinal.1), (1...31).contains(dayNumber)
        {
            var components = calendar.dateComponents([.year, .month], from: start)
            components.day = dayNumber
            if let date = calendar.date(from: components), date >= start { return date }
            components.month! += 1
            return calendar.date(from: components)
        }
        return nil
    }

    /// "8:00 AM - 10:00 AM", "between 8 and 10 am", "at 9:30am": minutes past midnight for the
    /// start and the end (one time is an hour). Nothing when no time is written.
    static func window(in text: String) -> (start: Int, end: Int)? {
        let pattern = /(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?/.ignoresCase()
        var times: [(hour: Int, minute: Int, meridian: String?)] = []
        for match in text.matches(of: pattern) {
            guard let hour = Int(match.1), (0...23).contains(hour) else { continue }
            let minute = match.2.flatMap { Int($0) } ?? 0
            let meridian = match.3.map { String($0).lowercased().filter(\.isLetter) }
            times.append((hour, minute, meridian))
        }
        guard !times.isEmpty else { return nil }
        // "between 8 and 10 am": the first time borrows the second's am/pm.
        let lastMeridian = times.last?.meridian
        func minutes(_ time: (hour: Int, minute: Int, meridian: String?)) -> Int {
            var hour = time.hour
            let meridian = time.meridian ?? lastMeridian
            if meridian == "pm", hour < 12 { hour += 12 }
            if meridian == "am", hour == 12 { hour = 0 }
            if meridian == nil, hour < 7 { hour += 12 }  // a service call at "2" is at 2 PM
            return hour * 60 + time.minute
        }
        let start = minutes(times[0])
        let end = times.count > 1 ? minutes(times[1]) : start + 60
        return (start, max(start, end))
    }
}

/// One appointment, as the world will hold it: `event:mail-<business>-<yyyyMMdd>`, with the
/// calendar's own predicates so "what's on this week?" includes it, and - when the provider
/// comes to the house - `visitor.expected` on the house for the window, so "someone's in the
/// driveway" at ten on Thursday is "that'll be the pest people".
struct Appointment: Equatable, Sendable, Codable {
    var business: String
    var service: String
    var day: Date
    /// Minutes past midnight; nil for a day with no time given.
    var windowStart: Int?
    var windowEnd: Int?
    var atHome: Bool
    var cancelled: Bool
    var lastMail: Date

    var window: (start: Int, end: Int)? {
        windowStart.map { ($0, windowEnd ?? $0 + 60) }
    }

    var key: String {
        let who = business.lowercased().filter { $0.isLetter || $0.isNumber }
        return "\(who.isEmpty ? "someone" : who)-\(Appointment.dayFormatter.string(from: day))"
    }

    var entityID: EntityID { EntityID(rawValue: "event:mail-\(key)")! }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// When it starts and ends, on the clock: the window, or the working day.
    func span(zone: TimeZone) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.startOfDay(for: day)
        let (from, to) = window ?? (8 * 60, 18 * 60)
        return (
            start.addingTimeInterval(TimeInterval(from * 60)),
            start.addingTimeInterval(TimeInterval(to * 60))
        )
    }
}

/// Every appointment the mail has told the Bridge about, keyed by business and day.
struct AppointmentBook: Sendable, Codable {
    private(set) var appointments: [String: Appointment] = [:]

    /// Folds one mail's reading in. `atHome` is the Bridge's own finding - the mail prints
    /// April's street - with the model's guess behind it. Returns the appointment it touched.
    @discardableResult
    mutating func apply(
        _ reading: AppointmentReading, mailedOn date: Date, zone: TimeZone, atHome: Bool? = nil
    ) -> Appointment? {
        guard let day = MailDates.day(in: reading.dateWords, mailedOn: date, zone: zone),
            !reading.business.isEmpty
        else { return nil }
        let window = MailDates.window(in: reading.timeWords)
        let appointment = Appointment(
            business: reading.business, service: reading.service, day: day,
            windowStart: window?.start, windowEnd: window?.end,
            atHome: atHome ?? reading.atAprilsHome, cancelled: reading.isCancellation,
            lastMail: date)
        if let existing = appointments[appointment.key], existing.lastMail > date {
            return existing
        }
        appointments[appointment.key] = appointment
        return appointment
    }

    /// Appointments whose day is past are let go; the world expired their facts.
    mutating func forgetPast(now: Date, zone: TimeZone) {
        appointments = appointments.filter {
            $0.value.span(zone: zone).end.addingTimeInterval(86_400) > now
        }
    }

    /// What the world should hold: an event per appointment, and a visitor on the house for
    /// the ones at the house. A cancelled appointment holds nothing.
    func wanted(zone: TimeZone, house: EntityID) -> [String: FactLedger.Wanted] {
        var result: [String: FactLedger.Wanted] = [:]
        for (key, appointment) in appointments where !appointment.cancelled {
            let (start, end) = appointment.span(zone: zone)
            let title =
                appointment.service.isEmpty
                ? appointment.business : "\(appointment.service) (\(appointment.business))"
            var facts: [String: WorldJSONValue] = [
                "calendar.title": .string(title),
                "calendar.when": .string(AppointmentFacts.when(appointment, zone: zone)),
                "calendar.starts_at": .string(WorldJSON.timestamp(start)),
                "calendar.ends_at": .string(WorldJSON.timestamp(end)),
                "calendar.calendar": .string("Mail"),
            ]
            if appointment.atHome { facts["calendar.location"] = .string("home") }
            result["appointment:\(key)"] = FactLedger.Wanted(
                entityID: appointment.entityID, facts: facts,
                validUntil: end.addingTimeInterval(90 * 86_400))
            if appointment.atHome {
                result["appointment:\(key):visitor"] = FactLedger.Wanted(
                    entityID: house,
                    facts: [
                        "visitor.expected": .string(
                            "\(appointment.business)\(appointment.service.isEmpty ? "" : " for \(appointment.service)"), \(AppointmentFacts.when(appointment, zone: zone))"
                        )
                    ],
                    validUntil: end.addingTimeInterval(2 * 3_600))
            }
        }
        return result
    }
}

enum AppointmentFacts {
    /// Whether the mail prints April's own street: the surest sign the provider is coming to
    /// the house. `homeStreets` are the street lines of her own card, lowercased. Evidence
    /// only ever confirms: a mail without the street says nothing either way, and the model's
    /// reading of the words stands.
    static func isAtHome(_ message: MailMessage, homeStreets: [String]) -> Bool? {
        let text = (message.subject + " " + message.text).lowercased()
        return homeStreets.contains { !$0.isEmpty && text.contains($0) } ? true : nil
    }

    /// "Thursday, September 18, 8:00–10:00 AM" or "Thursday, September 18 (time not given)".
    /// "Wednesday, September 16, 8–10 AM", with the year when it is not this one (#206).
    static func when(_ appointment: Appointment, zone: TimeZone, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        formatter.dateFormat =
            calendar.component(.year, from: appointment.day)
                == calendar.component(.year, from: now) ? "EEEE, MMMM d" : "EEEE, MMMM d, yyyy"
        let day = formatter.string(from: appointment.day)
        guard let window = appointment.window else { return "\(day) (time not given)" }
        return "\(day), \(clock(window.start))–\(clock(window.end))"
    }

    static func clock(_ minutes: Int) -> String {
        let hour24 = minutes / 60 % 24
        let minute = minutes % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "AM" : "PM"
        return minute == 0
            ? "\(hour12) \(suffix)" : String(format: "%d:%02d %@", hour12, minute, suffix)
    }
}
