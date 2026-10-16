import Foundation
import WorldCore

/// The families a page carries beside its thirty, folded: each subject's sensor readings as one
/// `environment.now`, its forecasts as one `forecast.outlook` (#231,
/// `docs/page-quality-plan.md`). On 2026-10-16 Beaky's thirty held seven sensor readings and
/// six forecasts - and one thing April had told her. A folded entry is made for the page and
/// never stored: it is as new as its newest reading, lasts as long as its shortest, and its
/// `derived_from` names every reading, so Why? still walks to them.
enum PageFolding {
    static let producer = FactProducer(kind: "world", id: "page", version: "1")

    static func fold(_ facts: [Fact]) -> [Fact] {
        var groups: [String: [Fact]] = [:]
        var order: [String] = []
        for fact in facts where fact.value != .null {
            guard let family = family(of: fact.predicate) else { continue }
            let key = "\(fact.subjectID.rawValue)\u{1}\(family)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(fact)
        }
        return order.compactMap { key in
            guard let readings = groups[key], let first = readings.first,
                let family = family(of: first.predicate)
            else { return nil }
            let words =
                family == WorldFacts.environmentPrefix
                ? environment(readings) : outlook(readings)
            guard !words.isEmpty else { return nil }
            return try? Fact(
                subjectID: first.subjectID,
                predicate: family == WorldFacts.environmentPrefix
                    ? WorldFacts.environmentNow : WorldFacts.forecastOutlook,
                value: .string(words),
                epistemic: EpistemicState(
                    type: first.epistemic.type,
                    confidence: readings.map(\.epistemic.confidence).min() ?? 1),
                validFrom: readings.map(\.validFrom).max() ?? first.validFrom,
                validTo: readings.compactMap(\.validTo).min(),
                derivedFrom: readings.map { .fact($0.factID) },
                producer: producer)
        }
    }

    private static func family(of predicate: String) -> String? {
        WorldKnowledgeLimits.foldedPrefixes.first { predicate.hasPrefix($0) }
    }

    // MARK: - Readings

    /// The order a reading is said in; the rest follow alphabetically.
    private static let readingOrder = [
        "temperature", "humidity", "light", "wind", "pm25", "pressure", "power",
    ]

    /// "temperature 51.7°F, humidity 89%, light 0 lux, wind 0 mph, PM2.5 2.7 µg/m³, pressure
    /// 1010.3 hPa" - each reading in its units, from the predicate's own suffix.
    ///
    /// The light's trend rides with the light itself - "light 120 lux, dimming" - the way
    /// Mango says it: which way the sky is going is the point of the reading at dusk.
    static func environment(_ readings: [Fact]) -> String {
        let trendKey = "light_trend"
        var trend: String?
        if let fact = readings.first(where: {
            $0.predicate == WorldFacts.environmentPrefix + trendKey
        }), case .string(let words) = fact.value {
            trend = words
        }
        var named = readings.compactMap { fact -> (rank: Int, name: String, text: String)? in
            let key = String(fact.predicate.dropFirst(WorldFacts.environmentPrefix.count))
            guard key != trendKey else { return nil }
            let (label, unit) = labelAndUnit(key)
            let rank = readingOrder.firstIndex { key.hasPrefix($0) } ?? readingOrder.count
            var said = "\(label) \(text(fact.value))\(unit)"
            if key == "light_lux", let trend { said += ", \(trend)" }
            return (rank, key, said)
        }
        // A trend with no reading beside it still says which way the light is going.
        if let trend, !readings.contains(where: { $0.predicate.hasSuffix(".light_lux") }) {
            named.append((readingOrder.firstIndex(of: "light")!, trendKey, "light \(trend)"))
        }
        return named.sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }.map(\.text)
            .joined(separator: ", ")
    }

    private static let units: [String: String] = [
        "f": "°F", "c": "°C", "percent": "%", "lux": " lux", "mph": " mph", "ugm3": " µg/m³",
        "hpa": " hPa", "w": " W", "in": " in", "ppm": " ppm",
    ]

    private static func labelAndUnit(_ key: String) -> (String, String) {
        var parts = key.split(separator: "_").map(String.init)
        var unit = ""
        if parts.count > 1, let known = units[parts.last!] {
            unit = known
            parts.removeLast()
        }
        let label = parts.joined(separator: " ")
        return (label == "pm25" ? "PM2.5" : label, unit)
    }

    private static func text(_ value: WorldJSONValue) -> String {
        switch value {
        case .number(let number):
            number == number.rounded() ? String(Int(number)) : String(format: "%.1f", number)
        case .string(let text): text
        case .bool(let flag): flag ? "yes" : "no"
        default: ""
        }
    }

    // MARK: - Forecasts

    private static let periodOrder = ["today", "tonight", "tomorrow"]

    /// "today: Partly Cloudy, high 64°, low 50°; tonight: Mostly Clear; tomorrow: ..." - each
    /// period's own words; a number (`forecast.tomorrow.high_f`) only for a period with no
    /// words of its own, since the words already say it.
    static func outlook(_ readings: [Fact]) -> String {
        var summaries: [String: String] = [:]
        var numbers: [String: [String]] = [:]
        for fact in readings {
            let key = String(fact.predicate.dropFirst(WorldFacts.forecastPrefix.count))
            let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
            guard let period = parts.first else { continue }
            if parts.count == 1, case .string(let words) = fact.value {
                summaries[period] = words
            } else if parts.count == 2 {
                let (label, unit) = labelAndUnit(parts[1])
                numbers[period, default: []].append(
                    "\(label) \(text(fact.value))\(unit == "°F" ? "°" : unit)")
            }
        }
        let periods = Set(summaries.keys).union(numbers.keys).sorted {
            (periodOrder.firstIndex(of: $0) ?? periodOrder.count, $0)
                < (periodOrder.firstIndex(of: $1) ?? periodOrder.count, $1)
        }
        return periods.compactMap { period in
            let label = period.replacingOccurrences(of: "_", with: " ")
            if let words = summaries[period] { return "\(label): \(words)" }
            guard let said = numbers[period]?.sorted(), !said.isEmpty else { return nil }
            return "\(label): " + said.joined(separator: ", ")
        }.joined(separator: "; ")
    }

    // MARK: - The calendar

    /// Each event and each reminder in one entry: "Church - Sunday, October 18 at 9:30 AM -
    /// at Unitarian Universalist Congregation, Freeland - on the Home calendar" was four lines,
    /// title, when, location, and calendar (#232). Anything that is neither passes through.
    static func foldCalendar(_ facts: [Fact]) -> [Fact] {
        var groups: [EntityID: [Fact]] = [:]
        var order: [EntityID] = []
        var others: [Fact] = []
        for fact in facts {
            guard calendarKind(of: fact) != nil, fact.value != .null else {
                others.append(fact)
                continue
            }
            if groups[fact.subjectID] == nil { order.append(fact.subjectID) }
            groups[fact.subjectID, default: []].append(fact)
        }
        let folded = order.compactMap { subject -> Fact? in
            guard let parts = groups[subject], let first = parts.first,
                let kind = calendarKind(of: first)
            else { return nil }
            let words =
                kind == "calendar." ? event(parts) : reminder(parts)
            guard !words.isEmpty else { return nil }
            return try? Fact(
                subjectID: subject,
                predicate: kind == "calendar." ? WorldFacts.calendarEvent : WorldFacts.reminderItem,
                value: .string(words),
                epistemic: first.epistemic,
                validFrom: parts.map(\.validFrom).max() ?? first.validFrom,
                validTo: parts.compactMap(\.validTo).min(),
                derivedFrom: parts.map { .fact($0.factID) },
                producer: producer)
        }
        return others + folded
    }

    private static func calendarKind(of fact: Fact) -> String? {
        let raw = fact.subjectID.rawValue
        if raw.hasPrefix("event:") && fact.predicate.hasPrefix("calendar.") { return "calendar." }
        if raw.hasPrefix("reminder:") && fact.predicate.hasPrefix("reminder.") {
            return "reminder."
        }
        return nil
    }

    private static func field(_ parts: [Fact], _ predicate: String) -> WorldJSONValue? {
        parts.first { $0.predicate == predicate }?.value
    }

    private static func words(_ value: WorldJSONValue?) -> String? {
        switch value {
        case .string(let text)?:
            let flat = text.split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }.joined(separator: ", ")
            if let id = EntityID(rawValue: flat), flat.contains(":") { return name(of: id) }
            return flat.isEmpty ? nil : flat
        case .array(let values)?:
            let named = values.compactMap { words($0) }
            return named.isEmpty ? nil : named.joined(separator: ", ")
        default: return nil
        }
    }

    private static func isTrue(_ value: WorldJSONValue?) -> Bool {
        if case .bool(true)? = value { return true }
        return false
    }

    /// "person:jesse" as "Jesse"; the world's ids name a person by slug.
    private static func name(of id: EntityID) -> String {
        let raw = id.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        return raw[raw.index(after: colon)...].split(separator: "-").map(\.capitalized)
            .joined(separator: " ")
    }

    static func event(_ parts: [Fact]) -> String {
        var said: [String] = []
        if let title = words(field(parts, "calendar.title")) { said.append(title) }
        if let when = words(field(parts, "calendar.when")) { said.append(when) }
        if let place = words(field(parts, "calendar.location")) { said.append("at \(place)") }
        if let with = words(field(parts, "calendar.with")) { said.append("with \(with)") }
        if let calendar = words(field(parts, "calendar.calendar")) {
            said.append("on the \(calendar) calendar")
        }
        return said.joined(separator: " - ")
    }

    static func reminder(_ parts: [Fact]) -> String {
        var said: [String] = []
        if let title = words(field(parts, "reminder.title")) { said.append(title) }
        if let due = words(field(parts, "reminder.due")) { said.append("due \(due)") }
        if let who = words(field(parts, "reminder.for")) { said.append("for \(who)") }
        if let priority = words(field(parts, "reminder.priority")) {
            said.append("\(priority) priority")
        }
        if let list = words(field(parts, "reminder.list")) { said.append("on the \(list) list") }
        if isTrue(field(parts, "reminder.completed")) { said.append("done") }
        return said.joined(separator: " - ")
    }
}
