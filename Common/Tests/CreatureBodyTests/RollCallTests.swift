import Common
import Foundation
import Logging
import Synchronization
import Testing
import WorldCore

@testable import creature_body

/// `creature-body` and Creature Server start with the machine, in either order. On 2026-11-24 the
/// body came up two seconds first, its one look at the list of creatures failed, and it said
/// nothing about any bird until it was restarted (#301).
@Suite("Who the creatures are", .timeLimit(.minutes(1)))
struct RollCallTests {
    private typealias Names = [CreatureIdentifier: String]

    /// What was told to the world.
    private actor Told {
        private(set) var subjects: [EntityID] = []
        func note(_ events: [WorldEventEnvelope]) { subjects += events.flatMap(\.subjectIDs) }
    }

    private func state(_ told: Told) -> BodyState {
        BodyState(
            configuration: BodyConfiguration(), logger: Logger(label: "roll-call-tests")
        ) { await told.note($0) }
    }

    private func report(_ id: CreatureIdentifier, to state: BodyState) async {
        await state.take(creatureID: id, facts: ["body.board_temperature_f": .number(99)])
    }

    private func rollCall(
        _ state: BodyState, pause: @escaping @Sendable (Duration) async throws -> Void = { _ in },
        answers: [Result<Names, ServerError>]
    ) -> RollCall {
        let remaining = Mutex(answers)
        return RollCall(state: state, logger: Logger(label: "roll-call-tests"), pause: pause) {
            remaining.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
        }
    }

    @Test("A body that starts before the server learns the birds when they report")
    func learnsAfterTheServerComesUp() async throws {
        let told = Told()
        let state = state(told)
        // Each pause is handed to the test, and waits there: one time round the loop.
        let (pauses, paused) = AsyncStream.makeStream(of: Duration.self)
        let calls = rollCall(
            state,
            pause: { length in
                paused.yield(length)
                if length == RollCall.afterAnswer { try await Task.sleep(for: .seconds(60)) }
            },
            answers: [
                .failure(.serverError("not up yet")), .failure(.serverError("not up yet")),
                .success(["beaky-id": "Beaky", "mango-id": "Mango"]),
            ])
        // The start: the server is not up.
        #expect(await calls.ask() == false)
        await report("beaky-id", to: state)
        #expect(await told.subjects.isEmpty)

        let running = Task { await calls.run() }
        var lengths = pauses.makeAsyncIterator()
        // Still not up; asked again soon, when the next report comes.
        #expect(await lengths.next() == RollCall.afterNoAnswer)
        await report("beaky-id", to: state)
        // Up.
        #expect(await lengths.next() == RollCall.afterAnswer)
        running.cancel()
        await running.value

        await report("beaky-id", to: state)
        await report("mango-id", to: state)
        #expect(
            await told.subjects == [
                try EntityID(validating: "character:beaky"),
                try EntityID(validating: "character:mango"),
            ])
    }

    @Test("A server that names no creatures has not loaded them: it is asked again soon")
    func anEmptyListIsNoAnswer() async {
        let state = state(Told())
        #expect(await rollCall(state, answers: [.success([:])]).ask() == false)
        #expect(await rollCall(state, answers: [.success(["beaky-id": "Beaky"])]).ask())
    }

    @Test("A creature already named asks nothing; a new name replaces the old")
    func namedCreaturesAskNothing() async throws {
        let told = Told()
        let state = state(told)
        await state.learn(["beaky-id": "Beeky"])
        await state.learn(["beaky-id": "Beaky"])
        await report("beaky-id", to: state)
        #expect(await told.subjects == [try EntityID(validating: "character:beaky")])

        // Nothing waits to be asked: a report that did would come before this one.
        let asked = Mutex(0)
        let (pauses, paused) = AsyncStream.makeStream(of: Duration.self)
        let calls = RollCall(
            state: state, logger: Logger(label: "roll-call-tests"),
            pause: { length in
                paused.yield(length)
                try await Task.sleep(for: .seconds(60))
            },
            list: {
                asked.withLock { $0 += 1 }
                return .success(["beaky-id": "Beaky"])
            })
        let running = Task { await calls.run() }
        await report("beaky-id", to: state)
        await report("stranger-id", to: state)
        var lengths = pauses.makeAsyncIterator()
        _ = await lengths.next()
        running.cancel()
        await running.value
        #expect(asked.withLock { $0 } == 1)
    }

    @Test("A Dynamixel report's own name is enough")
    func aReportThatNamesItselfIsKnown() async throws {
        let told = Told()
        let state = state(told)
        await state.take(
            creatureID: "kenny-id", name: "Kenny",
            facts: ["body.board_temperature_f": .number(99)])
        #expect(await told.subjects == [try EntityID(validating: "character:kenny")])
    }
}
