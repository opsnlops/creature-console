import Foundation
import Testing

@testable import Information_Bridge

@Suite("Pace")
struct PaceTests {
    @Test("A strict sleep waits about as long as asked, and no longer")
    func sleepsOnTheClock() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        try await Pace.sleep(seconds: 0.3)
        let elapsed = clock.now - start
        #expect(elapsed >= .milliseconds(280))
        #expect(elapsed < .seconds(2))
    }

    @Test("Cancelling the task ends the sleep at once")
    func cancels() async throws {
        let task = Task { try await Pace.sleep(seconds: 30) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.now - start < .seconds(2))
    }

    @Test("The test host never starts the Bridge")
    func testHostStaysQuiet() {
        #expect(BridgeStore.isHostingTests)
    }
}
