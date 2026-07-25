import SwiftUI
import Testing

@testable import Creature_Console

@Suite("FixtureControlService byte conversion")
struct FixtureControlServiceTests {

    @Test("converts normal components to DMX bytes")
    func convertsNormalComponents() {
        #expect(FixtureControlService.byte(0.0) == 0)
        #expect(FixtureControlService.byte(1.0) == 255)
        #expect(FixtureControlService.byte(0.5) == 128)
    }

    @Test("NaN does not trap and maps to zero (issue #55)")
    func nanMapsToZero() {
        #expect(FixtureControlService.byte(CGFloat.nan) == 0)
        #expect(FixtureControlService.byte(CGFloat.signalingNaN) == 0)
    }

    @Test("infinite components do not trap")
    func infiniteDoesNotTrap() {
        #expect(FixtureControlService.byte(CGFloat.infinity) == 0)
        #expect(FixtureControlService.byte(-CGFloat.infinity) == 0)
    }

    @Test("out-of-range components clamp instead of trapping")
    func outOfRangeClamps() {
        // Extended-range colors (Display P3 → sRGB) can land outside 0...1.
        #expect(FixtureControlService.byte(-0.25) == 0)
        #expect(FixtureControlService.byte(1.75) == 255)
        #expect(FixtureControlService.byte(CGFloat.greatestFiniteMagnitude) == 255)
        #expect(FixtureControlService.byte(-CGFloat.greatestFiniteMagnitude) == 0)
    }
}
