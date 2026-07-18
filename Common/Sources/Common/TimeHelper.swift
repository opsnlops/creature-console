import Foundation

public struct TimeHelper {


    /**
     Print out dates in my local time zone
     */
    public static func formatToLocalTime(_ date: Date) -> String {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"

        // Set the formatter's time zone to the system's current local time zone
        formatter.timeZone = TimeZone.current

        return formatter.string(from: date)
    }

    /// Formats a number of seconds as a clock-style `M:SS` duration (e.g. `75` → `"1:15"`).
    public static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// `formatDuration` with an optional tenths-of-a-second digit (`m:ss.t`) for scrub/hover
    /// readouts where sub-second position matters. Computed in integer tenths (rounded) so binary
    /// floating-point can't drop a digit — e.g. 75.6 stored as 75.5999… still reads "1:15.6".
    public static func formatDuration(_ seconds: Double, withTenths: Bool) -> String {
        guard withTenths else { return formatDuration(seconds) }
        let totalTenths = Int((max(0, seconds) * 10).rounded())
        return String(
            format: "%d:%02d.%d", totalTenths / 600, (totalTenths / 10) % 60, totalTenths % 10)
    }

    /// A configured, reused formatter for `formatEpochMillis`. `DateFormatter` is expensive
    /// to build; reading a configured instance is safe to share.
    private static let epochMillisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// Formats Unix epoch milliseconds as `yyyy-MM-dd HH:mm`, or `"—"` when `nil`.
    public static func formatEpochMillis(_ millis: Int64?) -> String {
        guard let millis else { return "—" }
        let date = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        return epochMillisFormatter.string(from: date)
    }

}
