import Testing
@testable import Common

@Suite("Common package smoke suite")
struct CommonSmokeTests {
    @Test("Can construct mock animation")
    func constructMockAnimation() throws {
        let animation = Animation.mock()
        #expect(!animation.tracks.isEmpty)
    }
}
