import Common
import SwiftUI

extension View {
    /// Observes a single job's lifecycle via `JobStatusStore.events(forJob:)`, re-subscribing
    /// whenever `jobId` changes and delivering each event to the callbacks on the MainActor.
    ///
    /// This replaces the hand-rolled `.task(id:) { … for await event in events(forJob:) {
    /// switch … } }` block (plus its manual observing-`Task` and `.onDisappear` cancel) that
    /// every job panel copied. `.task(id:)` owns cancellation — on `jobId` change and on
    /// disappear — so callers no longer track the observing task themselves (issue #8, #7).
    ///
    /// The `.task` operation runs off the MainActor, so each callback is hopped onto it, matching
    /// the per-site `await MainActor.run { … }` the call sites used to write by hand.
    func watchJob(
        _ jobId: String?,
        onUpdate: @escaping @MainActor (JobStatusStore.JobInfo) -> Void = { _ in },
        onTerminal: @escaping @MainActor (JobStatusStore.JobInfo) -> Void,
        onRemoved: @escaping @MainActor () -> Void
    ) -> some View {
        task(id: jobId) {
            guard let jobId else { return }
            for await event in await JobStatusStore.shared.events(forJob: jobId) {
                switch event {
                case .updated(let info): await MainActor.run { onUpdate(info) }
                case .terminal(let info): await MainActor.run { onTerminal(info) }
                case .removed: await MainActor.run { onRemoved() }
                }
            }
        }
    }
}
