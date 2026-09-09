import Foundation
import WorldCore

protocol WorldEventStore: Sendable {
    func append(_ event: WorldEventEnvelope, receivedAt: Date) async throws -> EventAppendResult
    func isProcessed(eventID: EventID) async throws -> Bool
    func markProcessed(eventID: EventID, processedAt: Date) async throws
}

protocol WorldFactStore: Sendable {
    func save(_ fact: Fact) async throws
}

protocol WorldTimerStore: Sendable {
    func schedule(_ timer: WorldTimer) async throws
    func cancel(timerID: TimerID, canceledAt: Date) async throws -> Bool
    func recoverable(limit: Int) async throws -> [WorldTimer]
    func claim(timerID: TimerID, dueAt: Date, firingAt: Date) async throws -> WorldTimer?
    func markFired(timerID: TimerID, dueAt: Date, firedAt: Date) async throws -> Bool
}

protocol WorldEventSink: Sendable {
    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance
}

extension WorldEventRepository: WorldEventStore {}
extension FactRepository: WorldFactStore {}
extension WorldTimerRepository: WorldTimerStore {}
extension World: WorldEventSink {}
