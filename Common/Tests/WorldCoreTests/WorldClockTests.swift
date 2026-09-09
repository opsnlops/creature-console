import Foundation
import Testing
import WorldCore

@Suite("World clocks")
struct WorldClockTests {
    @Test("Manual clock wakes sleepers only when their deadline is reached")
    func manualClockAdvancesDeterministically() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = ManualWorldClock(now: start)
        let sleeper = Task {
            try await clock.sleep(until: start.addingTimeInterval(10))
        }
        while await clock.pendingSleepCount == 0 {
            await Task.yield()
        }

        try await clock.advance(by: 9)
        #expect(await clock.now == start.addingTimeInterval(9))
        #expect(await clock.pendingSleepCount == 1)

        try await clock.advance(by: 1)
        try await sleeper.value
        #expect(await clock.pendingSleepCount == 0)
    }

    @Test("Manual clock rejects backward movement")
    func manualClockRejectsBackwardMovement() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = ManualWorldClock(now: start)

        await #expect(
            throws: ManualWorldClockError.cannotMoveBackward(
                current: start,
                requested: start.addingTimeInterval(-1)
            )
        ) {
            try await clock.advance(by: -1)
        }
    }

    @Test("Canceling a manual clock sleep removes its continuation")
    func manualClockSleepIsCancelable() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = ManualWorldClock(now: start)
        let sleeper = Task {
            try await clock.sleep(until: start.addingTimeInterval(10))
        }
        while await clock.pendingSleepCount == 0 {
            await Task.yield()
        }

        sleeper.cancel()
        await #expect(throws: CancellationError.self) {
            try await sleeper.value
        }
        #expect(await clock.pendingSleepCount == 0)
    }

    @Test("Timer identifiers are derived from stable semantic keys")
    func timerIdentifiersUseStableKeys() throws {
        let first = try TimerID.stable("calendar-event-123:departure-due")
        let second = try TimerID.stable("calendar-event-123:departure-due")

        #expect(first == second)
        #expect(first.rawValue == "timer:calendar-event-123:departure-due")
        #expect(throws: WorldIdentifierError.self) {
            try TimerID.stable("Not A Valid Key")
        }
    }
}
