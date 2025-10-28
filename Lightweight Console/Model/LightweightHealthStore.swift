import Common
import Foundation

struct LightweightHealthSnapshot: Sendable {
    let report: BoardSensorReport
}

actor LightweightHealthStore {
    static let shared = LightweightHealthStore()

    private var latestReports: [CreatureIdentifier: BoardSensorReport] = [:]
    private var continuations: [UUID: AsyncStream<LightweightHealthSnapshot>.Continuation] = [:]

    private init() {}

    func updates() -> AsyncStream<LightweightHealthSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation

            continuation.onTermination = { [weak self] _ in
                Task { [id] in
                    await self?.removeContinuation(id)
                }
            }
        }
    }

    func latestReport(for creatureId: CreatureIdentifier) -> BoardSensorReport? {
        latestReports[creatureId]
    }

    func record(boardReport: BoardSensorReport) {
        latestReports[boardReport.creatureId] = boardReport
        broadcast(boardReport)
    }

    private func broadcast(_ report: BoardSensorReport) {
        let snapshot = LightweightHealthSnapshot(report: report)
        continuations.values.forEach { $0.yield(snapshot) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
