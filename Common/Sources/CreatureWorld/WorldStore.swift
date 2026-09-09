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

extension WorldEventRepository: WorldEventStore {}
extension FactRepository: WorldFactStore {}
