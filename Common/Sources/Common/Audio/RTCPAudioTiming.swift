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

    public static func presentationDeadlineIsPlausible(
        _ plan: RTCPPlayoutPlan,
        packetArrival: ContinuousClock.Instant,
        commonPlayoutDelay: Duration,
        maximumDifference: Duration = .milliseconds(10)
    ) -> Bool {
        let expectedDeadline = packetArrival.advanced(by: commonPlayoutDelay)
        return absoluteDuration(from: expectedDeadline, to: plan.presentationDeadline)
            <= maximumDifference
    }

    public static func classifyEnqueue(
        _ plan: RTCPPlayoutPlan,
        now: ContinuousClock.Instant,
        lateTolerance: Duration = .milliseconds(2)
    ) -> RTCPEnqueueState {
        if now < plan.enqueueDeadline {
            return .wait
        }
        if plan.enqueueDeadline.duration(to: now) > lateTolerance {
            return .missed
        }
        return .ready
    }

    private static func durationSeconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func absoluteDuration(
        from first: ContinuousClock.Instant,
        to second: ContinuousClock.Instant
    ) -> Duration {
        first <= second ? first.duration(to: second) : second.duration(to: first)
    }
}

public struct TimedRTCPSenderReport: Equatable, Sendable {
    public let report: RTCPSenderReport
    public let receivedAt: ContinuousClock.Instant

    public init(report: RTCPSenderReport, receivedAt: ContinuousClock.Instant) {
        self.report = report
        self.receivedAt = receivedAt
    }

    public func isFresh(
        at now: ContinuousClock.Instant,
        maximumAge: Duration = .milliseconds(2_500)
    ) -> Bool {
        receivedAt <= now && receivedAt.duration(to: now) <= maximumAge
    }
}

public struct RTCPReportCache: Sendable {
    private let capacity: Int
    private var reports: [UInt32: TimedRTCPSenderReport] = [:]
    private var insertionOrder: [UInt32] = []

    public init(capacity: Int = 8) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var count: Int { reports.count }

    public mutating func store(
        _ report: RTCPSenderReport,
        receivedAt: ContinuousClock.Instant
    ) {
        let synchronizationSource = report.synchronizationSource
        if reports[synchronizationSource] == nil {
            if reports.count >= capacity, let oldest = insertionOrder.first {
                reports.removeValue(forKey: oldest)
                insertionOrder.removeFirst()
            }
            insertionOrder.append(synchronizationSource)
        }
        reports[synchronizationSource] = TimedRTCPSenderReport(
            report: report,
            receivedAt: receivedAt
        )
    }

    public func report(for synchronizationSource: UInt32) -> TimedRTCPSenderReport? {
        reports[synchronizationSource]
    }
}

public struct RTCPClockPair: Sendable {
    public let systemDate: Date
    public let continuousInstant: ContinuousClock.Instant

    public init(systemDate: Date, continuousInstant: ContinuousClock.Instant) {
        self.systemDate = systemDate
        self.continuousInstant = continuousInstant
    }

    public static func capture() -> RTCPClockPair {
        RTCPClockPair(systemDate: Date(), continuousInstant: .now)
    }

    public func continuousInstant(for date: Date) -> ContinuousClock.Instant {
        continuousInstant.advanced(by: .seconds(date.timeIntervalSince(systemDate)))
    }
}

public struct RTCPPlayoutPlan: Equatable, Sendable {
    public let mediaDate: Date
    public let presentationDeadline: ContinuousClock.Instant
    public let enqueueDeadline: ContinuousClock.Instant

    public init(
        mediaDate: Date,
        presentationDeadline: ContinuousClock.Instant,
        enqueueDeadline: ContinuousClock.Instant
    ) {
        self.mediaDate = mediaDate
        self.presentationDeadline = presentationDeadline
        self.enqueueDeadline = enqueueDeadline
    }
}

public enum RTCPEnqueueState: Equatable, Sendable {
    case wait
    case ready
    case missed
}

public struct RTCPPlayoutPlanner: Sendable {
    public let clockPair: RTCPClockPair
    public let commonPlayoutDelay: Duration
    public let outputLatency: Duration

    public init(
        clockPair: RTCPClockPair,
        commonPlayoutDelay: Duration,
        outputLatency: Duration
    ) {
        self.clockPair = clockPair
        self.commonPlayoutDelay = commonPlayoutDelay
        self.outputLatency = max(outputLatency, .zero)
    }

    public func plan(
        report: RTCPSenderReport,
        rtpTimestamp: UInt32,
        queuedFrames: Int
    ) -> RTCPPlayoutPlan? {
        guard
            queuedFrames >= 0,
            let mediaDate = RTCPAudioTiming.date(forRTPTimestamp: rtpTimestamp, using: report)
        else {
            return nil
        }

        let presentationDate = mediaDate.addingTimeInterval(
            RTCPAudioTiming.timeInterval(for: commonPlayoutDelay)
        )
        let presentationDeadline = clockPair.continuousInstant(for: presentationDate)
        let queuedDuration = Duration.seconds(
            Double(queuedFrames) / Double(RTPAudioConstants.sampleRate)
        )
        return RTCPPlayoutPlan(
            mediaDate: mediaDate,
            presentationDeadline: presentationDeadline,
            enqueueDeadline: presentationDeadline.advanced(
                by: .zero - queuedDuration - outputLatency
            )
        )
    }
}

extension RTCPAudioTiming {
    fileprivate static func timeInterval(for duration: Duration) -> TimeInterval {
        durationSeconds(duration)
    }
}
