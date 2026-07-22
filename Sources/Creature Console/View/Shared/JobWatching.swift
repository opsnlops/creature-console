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
    /// `.task` inherits the view's MainActor isolation, so the `@MainActor` callbacks are
    /// called directly — no per-event hop.
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
                case .updated(let info): onUpdate(info)
                case .terminal(let info): onTerminal(info)
                case .removed: onRemoved()
                }
            }
        }
    }
}
