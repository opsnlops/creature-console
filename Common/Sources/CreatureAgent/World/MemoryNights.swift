import Foundation
import Logging

/// The nights asked to be remembered and not yet done, oldest first, worked through one at a
/// time (#262). A night that arrived while another was being remembered used to be skipped
/// ("Still remembering the last day; skipping") and never remembered. Now it waits behind that
/// one, and the night in hand stops waiting on the provider's batch and asks now. Kept on disk
/// beside the pending night, so a restart loses none.
actor MemoryNights {
    struct Night: Codable, Equatable, Sendable {
        /// `2026-10-22`, in the house's zone.
        var day: String
        /// The `memory.consolidate` event that asked.
        var run: String
    }

    typealias Work = @Sendable (Night) async -> Void

    private let file: URL?
    private let logger: Logger
    private var nights: [Night]
    private var working = false

    init(file: URL?, logger: Logger) {
        self.file = file
        self.logger = logger
        nights =
            file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Night].self, from: $0) } ?? []
    }

    /// Whether another night waits behind the one in hand: then a batch it is waiting on gives
    /// up and its stage is asked now.
    var isWaitedOn: Bool { nights.count > 1 }

    /// What is still to be remembered, the night in hand first.
    var waiting: [Night] { nights }

    /// Adds `night` and works through the nights with `work`, unless already at it. True when
    /// `night` waits behind another.
    @discardableResult
    func add(_ night: Night, _ work: @escaping Work) -> Bool {
        if !nights.contains(night) {
            nights.append(night)
            save()
        }
        return !start(work)
    }

    /// At a start: works through what was kept, `inProgress` - the night written down as
    /// pending when the process stopped - first.
    func resume(inProgress: Night?, _ work: @escaping Work) {
        if let inProgress, !nights.contains(inProgress) {
            nights.insert(inProgress, at: 0)
            save()
        }
        start(work)
    }

    /// Starts working through the nights unless already at it; true when this call started.
    @discardableResult
    private func start(_ work: @escaping Work) -> Bool {
        guard !working, !nights.isEmpty else { return false }
        working = true
        Task {
            while let night = next() {
                await work(night)
                done(night)
            }
        }
        return true
    }

    /// The night in hand, or nil - and no longer working - when none is left. One step, so a
    /// night added as the last one finishes is never stranded.
    private func next() -> Night? {
        guard let night = nights.first else {
            working = false
            return nil
        }
        return night
    }

    private func done(_ night: Night) {
        nights.removeAll { $0 == night }
        save()
    }

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(nights).write(to: file, options: .atomic)
        } catch {
            logger.warning(
                "Could not write the nights to remember", metadata: ["error": "\(error)"])
        }
    }
}
