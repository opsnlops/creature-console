import Foundation
import Testing

@testable import Common

@Suite("TimeHelper.formatDuration")
struct TimeHelperTests {

    @Test("m:ss with zero-padded seconds, rounded")
    func formatsMinutesSeconds() {
        #expect(TimeHelper.formatDuration(0) == "0:00")
        #expect(TimeHelper.formatDuration(9) == "0:09")
        #expect(TimeHelper.formatDuration(75) == "1:15")
        #expect(TimeHelper.formatDuration(75.6) == "1:16")  // rounds
        #expect(TimeHelper.formatDuration(600) == "10:00")
    }

    @Test("withTenths adds a tenths digit for scrub readouts, robust to float representation")
    func formatsWithTenths() {
        #expect(TimeHelper.formatDuration(75.6, withTenths: true) == "1:15.6")  // 75.5999… → .6
        #expect(TimeHelper.formatDuration(75.64, withTenths: true) == "1:15.6")  // rounds to nearest
        #expect(TimeHelper.formatDuration(75.66, withTenths: true) == "1:15.7")
        #expect(TimeHelper.formatDuration(0, withTenths: true) == "0:00.0")
        #expect(TimeHelper.formatDuration(600, withTenths: true) == "10:00.0")
        // withTenths:false matches the plain overload exactly.
        #expect(
            TimeHelper.formatDuration(75.6, withTenths: false) == TimeHelper.formatDuration(75.6))
    }

    @Test("negative durations clamp to zero with tenths")
    func clampsNegative() {
        #expect(TimeHelper.formatDuration(-5, withTenths: true) == "0:00.0")
    }
}
