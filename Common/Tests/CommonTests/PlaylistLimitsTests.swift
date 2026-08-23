import Foundation
import Testing

@testable import Common

@Suite("PlaylistLimits")
struct PlaylistLimitsTests {

    @Test("mirrors the server's accepted weight range")
    func mirrorsServerRange() {
        #expect(PlaylistLimits.minimumItemWeight == 1)
        #expect(PlaylistLimits.maximumItemWeight == 999)
        #expect(PlaylistLimits.itemWeightRange == 1...999)
    }

    @Test("accepts weights inside the range", arguments: [1, 2, 500, 998, 999] as [UInt32])
    func acceptsInRange(weight: UInt32) {
        #expect(PlaylistLimits.isValidWeight(weight))
        #expect(PlaylistLimits.weight(fromUserInput: String(weight)) == weight)
    }

    @Test("rejects weights outside the range", arguments: [0, 1000, UInt32.max] as [UInt32])
    func rejectsOutOfRange(weight: UInt32) {
        #expect(!PlaylistLimits.isValidWeight(weight))
        #expect(PlaylistLimits.weight(fromUserInput: String(weight)) == nil)
    }

    /// Whole-string parsing on purpose: "12x" is a typo, and silently reading it as 12 is how
    /// a user ends up with a weight they didn't ask for.
    @Test(
        "rejects text that isn't a plain whole number",
        arguments: ["", "  ", "12x", "1.5", "-4", "1e3", "٣", "٩٩", "0x10"])
    func rejectsNonNumericInput(text: String) {
        #expect(PlaylistLimits.weight(fromUserInput: text) == nil)
    }

    @Test("tolerates surrounding whitespace and an explicit plus")
    func toleratesWhitespace() {
        #expect(PlaylistLimits.weight(fromUserInput: "  42 ") == 42)
        // Swift's own integer parsing accepts a leading "+", and "+5" is an unambiguous 5.
        // No reason to be stricter than that.
        #expect(PlaylistLimits.weight(fromUserInput: "+5") == 5)
    }

    /// The total-weight helper accumulates wide, so a list of locally edited values that
    /// haven't been validated yet can't trap in a SwiftUI body.
    @Test("total weight accumulates without overflowing")
    func totalWeightIsWide() {
        let items = (0..<8).map { _ in
            PlaylistItem(animationId: UUID().uuidString, weight: UInt32.max)
        }
        #expect(items.totalWeight == UInt64(UInt32.max) * 8)
        #expect(items.percentage(of: items[0]) == 12.5)
    }

    @Test("percentages are zero when nothing has weight")
    func zeroWeightGivesZeroPercent() {
        let items = [PlaylistItem(animationId: UUID().uuidString, weight: 0)]
        #expect(items.totalWeight == 0)
        #expect(items.percentage(of: items[0]) == 0)
    }
}
