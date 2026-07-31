import Foundation

public enum RTCPAudioTiming {
    private static let ntpUnixEpochOffsetSeconds: Int64 = 2_208_988_800
    private static let ntpFractionScale = Double(UInt64(1) << 32)

    public static func date(forNTPTimestamp ntpTimestamp: UInt64) -> Date? {
        let ntpSeconds = Int64(ntpTimestamp >> 32)
        let unixSeconds = ntpSeconds - ntpUnixEpochOffsetSeconds
        let fraction = Double(UInt32(truncatingIfNeeded: ntpTimestamp)) / ntpFractionScale
        let interval = Double(unixSeconds) + fraction
        guard interval.isFinite else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    public static func date(
        forRTPTimestamp rtpTimestamp: UInt32,
        using report: RTCPSenderReport
    ) -> Date? {
        guard let reportDate = date(forNTPTimestamp: report.ntpTimestamp) else {
            return nil
        }
        let sampleDifference = signedRTPTimestampDifference(
            rtpTimestamp,
            reference: report.rtpTimestamp
        )
        return reportDate.addingTimeInterval(
            Double(sampleDifference) / Double(RTPAudioConstants.sampleRate)
        )
    }

    public static func mappingsAreCompatible(
        _ first: RTCPSenderReport,
        _ second: RTCPSenderReport,
        tolerance: Duration = .milliseconds(1)
    ) -> Bool {
        guard
            !first.canonicalName.isEmpty,
            first.canonicalName == second.canonicalName,
            let firstMappedDate = date(forRTPTimestamp: second.rtpTimestamp, using: first),
            let secondDate = date(forNTPTimestamp: second.ntpTimestamp)
        else {
            return false
        }

        let difference = abs(firstMappedDate.timeIntervalSince(secondDate))
        return difference <= durationSeconds(tolerance)
    }

    private static func durationSeconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
