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
            if let words = summaries[period] { return "\(period): \(words)" }
            guard let said = numbers[period]?.sorted(), !said.isEmpty else { return nil }
            return "\(period): " + said.joined(separator: ", ")
        }.joined(separator: "; ")
    }
}
