import Foundation
import WorldCore

/// When the world asks its minds to remember the day, and how memories are handed back to
/// them. The job itself runs in the mind (the mind owns its memories and the model key); the
/// world keeps the clock, the digest, and the facts.
struct MemoryConfiguration: Codable, Equatable, Sendable {
    /// Local time the day is consolidated; the day consolidated is the one that just ended.
    var hour: Int
    var minute: Int
    var timeZone: String
    /// How long an episode is handed to a mind in every prompt. The episode itself is kept for
    /// years; only its place in the prompt fades. April: "keep the fact summaries for a very
    /// long time."
    var episodeDays: Int
    /// The most episodes a single prompt carries, newest and most salient first.
    var episodesInPrompt: Int
    /// The most reflections a mind is handed (its own, newest first).
    var reflectionsInPrompt: Int
    /// The most beliefs a single prompt carries, most salient first. Beliefs never age out.
    var beliefsInPrompt: Int

    init(
        hour: Int = 3, minute: Int = 30, timeZone: String = "America/Los_Angeles",
        episodeDays: Int = 30, episodesInPrompt: Int = 10, reflectionsInPrompt: Int = 2,
        beliefsInPrompt: Int = 12
    ) {
        self.hour = hour
        self.minute = minute
        self.timeZone = timeZone
        self.episodeDays = episodeDays
        self.episodesInPrompt = episodesInPrompt
        self.reflectionsInPrompt = reflectionsInPrompt
        self.beliefsInPrompt = beliefsInPrompt
    }

    var zone: TimeZone { TimeZone(identifier: timeZone) ?? .current }

    /// The next consolidation after `now`, and the local day it consolidates.
    func nextRun(after now: Date) -> (dueAt: Date, day: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var due = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: now, direction: .forward)!
        if due <= now {
            due = calendar.date(byAdding: .day, value: 1, to: due)!
        }
        // The day that ends at the run: the local date one day before the run's date.
        let ended = calendar.date(byAdding: .day, value: -1, to: due)!
        return (due, Self.dayString(ended, in: zone))
    }

    static func dayString(_ date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// The local day's bounds, for a digest.
    static func bounds(ofDay day: String, in zone: TimeZone) -> (from: Date, to: Date)? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard
            let start = calendar.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return (start, calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    private enum CodingKeys: String, CodingKey {
        case hour, minute
        case timeZone = "time_zone"
        case episodeDays = "episode_days"
        case episodesInPrompt = "episodes_in_prompt"
        case reflectionsInPrompt = "reflections_in_prompt"
        case beliefsInPrompt = "beliefs_in_prompt"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MemoryConfiguration()
        self.init(
            hour: try container.decodeIfPresent(Int.self, forKey: .hour) ?? defaults.hour,
            minute: try container.decodeIfPresent(Int.self, forKey: .minute) ?? defaults.minute,
            timeZone: try container.decodeIfPresent(String.self, forKey: .timeZone)
                ?? defaults.timeZone,
            episodeDays: try container.decodeIfPresent(Int.self, forKey: .episodeDays)
                ?? defaults.episodeDays,
            episodesInPrompt: try container.decodeIfPresent(Int.self, forKey: .episodesInPrompt)
                ?? defaults.episodesInPrompt,
            reflectionsInPrompt: try container.decodeIfPresent(
                Int.self, forKey: .reflectionsInPrompt) ?? defaults.reflectionsInPrompt,
            beliefsInPrompt: try container.decodeIfPresent(Int.self, forKey: .beliefsInPrompt)
                ?? defaults.beliefsInPrompt)
        guard (0...23).contains(hour), (0...59).contains(minute),
            TimeZone(identifier: timeZone) != nil
        else { throw CreatureWorldConfigurationError.invalidRetention("memory") }
    }
}
