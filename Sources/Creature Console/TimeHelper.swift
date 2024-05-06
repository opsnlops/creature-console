
import Foundation


struct TimeHelper {
    

    /**
     Print out dates in my local time zone
     */
    static func formatToLocalTime(_ date: Date) -> String {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"

        // Set the formatter's time zone to the system's current local time zone
        formatter.timeZone = TimeZone.current

        return formatter.string(from: date)
    }

}
