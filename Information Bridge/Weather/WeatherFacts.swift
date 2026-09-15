import Foundation
import WorldCore

/// What the sky will do, as plain values the Bridge can turn into facts - WeatherKit's answer,
/// without WeatherKit's types, so the turning is testable on any machine.
struct WeatherSnapshot: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        var date: Date
        var condition: String
        var highF: Double
        var lowF: Double
        var rainChance: Double  // 0...1
        var rainInches: Double
        var sunrise: Date?
        var sunset: Date?
    }

    struct Hour: Equatable, Sendable {
        var date: Date
        var rainChance: Double
        var condition: String
    }

    struct Alert: Equatable, Sendable {
        var id: String
        var summary: String
        var severity: String
        var expires: Date?
    }

    var days: [Day]  // today first
    var hours: [Hour]  // from now, ascending
    var alerts: [Alert]
}

/// One fact the Bridge will cast: predicate, value, and until when it holds.
struct WeatherFact: Equatable, Sendable {
    var predicate: String
    var value: WorldJSONValue
    var validUntil: Date
}

/// The facts a snapshot makes, on the place the sky is over. Every value is in the words a bird
/// could say: temperatures are whole degrees, rain is "this evening around 6", not an ISO date -
/// except sunrise and sunset, where the clock time *is* the fact.
enum WeatherFacts {
    static let rainThreshold = 0.4

    static let meanings: [String: String] = [
        "forecast.today": "what the sky will do today: conditions, high and low, chance of rain",
        "forecast.today.high_f": "today's forecast high, degrees Fahrenheit",
        "forecast.today.low_f": "today's forecast low, degrees Fahrenheit",
        "forecast.today.rain_chance_percent": "chance of rain today, percent",
        "forecast.today.rain_in": "rain expected today, inches",
        "forecast.tonight": "what the sky will do tonight, from the hourly forecast",
        "forecast.tomorrow":
            "what the sky will do tomorrow: conditions, high and low, chance of rain",
        "forecast.tomorrow.high_f": "tomorrow's forecast high, degrees Fahrenheit",
        "forecast.tomorrow.low_f": "tomorrow's forecast low, degrees Fahrenheit",
        "forecast.tomorrow.rain_chance_percent": "chance of rain tomorrow, percent",
        "forecast.next_rain":
            "when rain is next likely, in human terms; or that none is coming soon",
        "sun.rise": "when the sun rises today, clock time",
        "sun.set": "when the sun sets today, clock time",
        "weather.alert":
            "a weather alert in force for the area, from the National Weather Service, until it expires",
    ]

    static func facts(from snapshot: WeatherSnapshot, now: Date, zone: TimeZone) -> [WeatherFact] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: endOfToday)!
        var facts: [WeatherFact] = []

        if let today = snapshot.days.first(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            facts += dayFacts(today, prefix: "forecast.today", until: endOfToday)
            if let sunrise = today.sunrise {
                facts.append(
                    WeatherFact(
                        predicate: "sun.rise", value: .string(clock(sunrise, zone: zone)),
                        validUntil: endOfToday))
            }
            if let sunset = today.sunset {
                facts.append(
                    WeatherFact(
                        predicate: "sun.set", value: .string(clock(sunset, zone: zone)),
                        validUntil: endOfToday))
            }
        }
        if let tomorrow = snapshot.days.first(where: {
            calendar.isDate($0.date, inSameDayAs: endOfToday)
        }) {
            facts += dayFacts(tomorrow, prefix: "forecast.tomorrow", until: endOfTomorrow)
        }
        if let tonight = tonight(snapshot.hours, now: now, calendar: calendar) {
            facts.append(
                WeatherFact(
                    predicate: "forecast.tonight", value: .string(tonight), validUntil: endOfToday))
        }
        facts.append(
            nextRain(
                snapshot.hours, days: snapshot.days, now: now, calendar: calendar,
                until: endOfTomorrow))
        if let alert = snapshot.alerts.first {
            facts.append(
                WeatherFact(
                    predicate: "weather.alert",
                    value: .string("\(alert.summary) (\(alert.severity))"),
                    validUntil: alert.expires ?? endOfToday))
        }
        return facts
    }

    private static func dayFacts(_ day: WeatherSnapshot.Day, prefix: String, until: Date)
        -> [WeatherFact]
    {
        let high = Int(day.highF.rounded())
        let low = Int(day.lowF.rounded())
        let chance = Int((day.rainChance * 100).rounded())
        var line = "\(day.condition), high \(high)°, low \(low)°"
        if chance >= 20 {
            line += ", \(chance)% chance of rain"
            if day.rainInches >= 0.05 {
                line += " (about \(inches(day.rainInches)))"
            }
        }
        var facts = [
            WeatherFact(predicate: prefix, value: .string(line), validUntil: until),
            WeatherFact(
                predicate: "\(prefix).high_f", value: .number(Double(high)), validUntil: until),
            WeatherFact(
                predicate: "\(prefix).low_f", value: .number(Double(low)), validUntil: until),
            WeatherFact(
                predicate: "\(prefix).rain_chance_percent", value: .number(Double(chance)),
                validUntil: until),
        ]
        if prefix == "forecast.today" {
            facts.append(
                WeatherFact(
                    predicate: "\(prefix).rain_in",
                    value: .number((day.rainInches * 100).rounded() / 100), validUntil: until))
        }
        return facts
    }

    /// The hours from 6 PM to midnight today, summed up: the most likely condition and the
    /// highest chance of rain.
    private static func tonight(_ hours: [WeatherSnapshot.Hour], now: Date, calendar: Calendar)
        -> String?
    {
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let evening = hours.filter { $0.date >= max(start, now) && $0.date < end }
        guard !evening.isEmpty else { return nil }
        let chance = evening.map(\.rainChance).max() ?? 0
        let condition = mostCommon(evening.map(\.condition)) ?? evening[0].condition
        var line = condition
        if chance >= 0.2 { line += ", \(Int((chance * 100).rounded()))% chance of rain" }
        return line
    }

    /// "this evening around 6", "tomorrow morning", or "not in the next two days". The hour
    /// says when; when no hour is likely but a day is - drizzle on and off, which never clears
    /// the bar in any one hour - the day says so, and the next rain agrees with the forecast it
    /// sits beside. (Beaky, the first night: "the forecast oddly also says no rain in the next
    /// two days.")
    private static func nextRain(
        _ hours: [WeatherSnapshot.Hour], days: [WeatherSnapshot.Day], now: Date,
        calendar: Calendar, until: Date
    ) -> WeatherFact {
        guard let first = hours.first(where: { $0.date >= now && $0.rainChance >= rainThreshold })
        else {
            let endOfToday = calendar.date(
                byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            if let day = days.first(where: {
                ($0.date >= calendar.startOfDay(for: now)) && $0.date < until
                    && $0.rainChance >= rainThreshold
            }) {
                let name = calendar.isDate(day.date, inSameDayAs: now) ? "today" : "tomorrow"
                let chance = Int((day.rainChance * 100).rounded())
                return WeatherFact(
                    predicate: "forecast.next_rain",
                    value: .string(
                        "\(name), \(day.condition.lowercased()) on and off, \(chance)% chance"),
                    validUntil: name == "today" ? endOfToday : until)
            }
            return WeatherFact(
                predicate: "forecast.next_rain", value: .string("not in the next two days"),
                validUntil: until)
        }
        let hour = calendar.component(.hour, from: first.date)
        let day: String =
            calendar.isDate(first.date, inSameDayAs: now)
            ? (hour < 5
                ? "before dawn"
                : hour < 12 ? "this morning" : hour < 17 ? "this afternoon" : "this evening")
            : calendar.isDate(
                first.date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!)
                ? (hour < 12
                    ? "tomorrow morning" : hour < 17 ? "tomorrow afternoon" : "tomorrow evening")
                : "in a couple of days"
        let clock =
            hour == 0
            ? "midnight" : hour == 12 ? "noon" : hour < 12 ? "\(hour) AM" : "\(hour - 12) PM"
        let when = day == "in a couple of days" ? day : "\(day) around \(clock)"
        return WeatherFact(
            predicate: "forecast.next_rain",
            value: .string("\(when), \(Int((first.rainChance * 100).rounded()))% chance"),
            validUntil: min(first.date, until))
    }

    private static func mostCommon(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    static func clock(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func inches(_ value: Double) -> String {
        value < 0.1
            ? "a trace"
            : value < 0.3
                ? "a quarter inch"
                : value < 0.6
                    ? "half an inch" : value < 1.2 ? "an inch" : "\(Int(value.rounded())) inches"
    }
}
