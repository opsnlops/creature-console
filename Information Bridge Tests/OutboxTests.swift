import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("The Bridge's outbox")
struct OutboxTests {
    private let house = try! EntityID(validating: "house:test-nest")

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "outbox-tests-\(UUID().uuidString.lowercased())")
    }

    @Test("A fact written down is delivered, in order, and remembered as sent")
    func deliversInOrder() async throws {
        let directory = temporaryDirectory()
        let outbox = try Outbox(directory: directory)
        let casts = Casts()
        await outbox.start { await casts.note($0) }
        let first = try BridgeFacts.hello(house: house, version: "t", host: "mac")
        let second = try BridgeFacts.online(version: "t", host: "mac")
        try await outbox.enqueue(first)
        try await outbox.enqueue(second)
        try await settle { await casts.events.count == 2 }
        #expect(await casts.events.map(\.eventID) == [first.eventID, second.eventID])
        let status = await outbox.current
        #expect(status.pending == 0)
        #expect(status.delivered == 2)
        #expect(status.recent.map(\.event.eventID) == [second.eventID, first.eventID])
        #expect(status.lastError == nil)
        await outbox.stop()
    }

    @Test("A world that is down keeps the fact waiting; it goes when the world is back")
    func retriesUntilTheWorldAnswers() async throws {
        let directory = temporaryDirectory()
        let outbox = try Outbox(directory: directory)
        let casts = Casts()
        let door = Door()
        await outbox.start { event in
            guard await door.isOpen else { throw DoorClosed() }
            await casts.note(event)
        }
        let fact = try BridgeFacts.hello(house: house, version: "t", host: "mac")
        try await outbox.enqueue(fact)
        try await settle { await outbox.current.lastError != nil }
        #expect(await outbox.current.pending == 1)
        #expect(await casts.events.isEmpty)
        await door.open()
        try await settle(timeout: .seconds(6)) { await casts.events.count == 1 }
        #expect(await outbox.current.pending == 0)
        #expect(await outbox.current.lastError == nil)
        #expect(await outbox.current.recent.first?.attempts == 2)
        await outbox.stop()
    }

    @Test("What was waiting when the Bridge quit is still waiting when it starts again")
    func survivesARestart() async throws {
        let directory = temporaryDirectory()
        let fact = try BridgeFacts.hello(house: house, version: "t", host: "mac")
        do {
            let outbox = try Outbox(directory: directory)
            try await outbox.enqueue(fact)  // never started: nothing delivers it
            #expect(await outbox.current.pending == 1)
        }
        let reopened = try Outbox(directory: directory)
        #expect(await reopened.current.pending == 1)
        let casts = Casts()
        await reopened.start { await casts.note($0) }
        try await settle { await casts.events.count == 1 }
        #expect(await casts.events.first?.eventID == fact.eventID)
        await reopened.stop()
    }

    @Test("A backlog goes in batches, in order, when the world takes many at once")
    func batchesABacklog() async throws {
        let directory = temporaryDirectory()
        let outbox = try Outbox(directory: directory)
        let events = try (1...250).map { _ in try BridgeFacts.online(version: "t", host: "mac") }
        for event in events { try await outbox.enqueue(event) }
        let batches = Batches()
        await outbox.start(
            cast: { await batches.note([$0]) }, castMany: { await batches.note($0) })
        try await settle { await batches.sizes.reduce(0, +) == 250 }
        #expect(await batches.sizes == [100, 100, 50])
        #expect(await batches.all.map(\.eventID) == events.map(\.eventID))
        #expect(await outbox.current.delivered == 250)
        await outbox.stop()
    }

    @Test("Bridge facts carry their source, their item id, and their window")
    func factShape() throws {
        let fact = try BridgeFacts.given(
            subject: house, predicate: "delivery.expected",
            value: .string("robot parts (UPS), today"),
            validFor: 3_600, source: "mail", itemID: "mail:abc")
        #expect(fact.type.rawValue == "facts.given")
        #expect(fact.source.id.rawValue == "bridge:mail")
        #expect(fact.source.kind == "bridge")
        #expect(fact.source.sourceEventID == "mail:abc")
        #expect(fact.payload["valid_for_seconds"] == .number(3_600))
        #expect(fact.epistemic.type == .reported)
        let online = try BridgeFacts.online(version: "0.1.0", host: "mac")
        #expect(online.subjectIDs == [BridgeFacts.bridgeID])
        #expect(online.payload["predicate"] == .string("bridge.online"))
    }

    private func settle(
        timeout: Duration = .seconds(3), until condition: @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !(await condition()) {
            guard clock.now < deadline else {
                Issue.record("Did not settle within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

private actor Door {
    private(set) var isOpen = false
    func open() { isOpen = true }
}

private struct DoorClosed: Error {}

private actor Batches {
    private(set) var sizes: [Int] = []
    private(set) var all: [WorldEventEnvelope] = []
    func note(_ events: [WorldEventEnvelope]) {
        sizes.append(events.count)
        all += events
    }
}
