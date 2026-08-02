import Foundation
import Testing

@testable import Common
@testable import Creature_Console

@Suite("JobStatusStore terminal-state handling")
struct JobStatusStoreTests {

    // The store is a shared actor, so every test uses a unique job id and cleans up after
    // itself to stay isolated.

    @Test("progress updates apply to a running job")
    func progressUpdatesApplyWhileRunning() async {
        let jobId = UUID().uuidString
        let store = JobStatusStore.shared

        await store.update(
            with: JobProgress(
                jobId: jobId, jobType: .dialog, status: .queued, progress: 0, details: nil))
        await store.update(
            with: JobProgress(
                jobId: jobId, jobType: .dialog, status: .running, progress: 0.6, details: nil))

        let info = await store.job(for: jobId)
        #expect(info?.status == .running)
        #expect(info?.progress == 0.6)

        await store.remove(jobId: jobId)
    }

    @Test("completion after progress marks the job terminal")
    func completionAfterProgressIsTerminal() async {
        let jobId = UUID().uuidString
        let store = JobStatusStore.shared

        await store.update(
            with: JobProgress(
                jobId: jobId, jobType: .dialog, status: .running, progress: 0.5, details: nil))
        await store.update(
            with: JobCompletion(
                jobId: jobId, jobType: .dialog, status: .completed, result: nil, details: nil))

        let info = await store.job(for: jobId)
        #expect(info?.status == .completed)
        #expect(info?.isTerminal == true)
        #expect(info?.progress == 1.0)

        await store.remove(jobId: jobId)
    }

    @Test("a late queued seed does not resurrect a completed job")
    func lateSeedDoesNotResurrectCompletedJob() async {
        let jobId = UUID().uuidString
        let store = JobStatusStore.shared

        // A fast job's websocket completion can land before the panel's optimistic seed
        // (queued/0.0, posted after the REST 202 returns). The seed must not win.
        await store.update(
            with: JobCompletion(
                jobId: jobId, jobType: .dialog, status: .completed, result: nil, details: nil))
        await store.update(
            with: JobProgress(
                jobId: jobId, jobType: .dialog, status: .queued, progress: 0, details: nil))

        let info = await store.job(for: jobId)
        #expect(info?.status == .completed)
        #expect(info?.isTerminal == true)
        #expect(info?.progress == 1.0)

        await store.remove(jobId: jobId)
    }

    @Test("events(forJob:) yields terminal exactly once and auto-removes the job")
    func perJobStreamTerminalAutoRemoves() async {
        let jobId = UUID().uuidString
        let store = JobStatusStore.shared

        await store.update(
            with: JobProgress(
                jobId: jobId, jobType: .dialog, status: .running, progress: 0.5, details: nil))

        var iterator = await store.events(forJob: jobId).makeAsyncIterator()

        // Registration replays the job's current state, proving the watcher is attached
        // before we complete the job (keeps the test deterministic).
        guard case .updated(let replayed) = await iterator.next() else {
            Issue.record("expected the replayed running state first")
            return
        }
        #expect(replayed.progress == 0.5)

        await store.update(
            with: JobCompletion(
                jobId: jobId, jobType: .dialog, status: .completed, result: nil, details: nil))

        guard case .terminal(let info) = await iterator.next() else {
            Issue.record("expected a terminal event after completion")
            return
        }
        #expect(info.status == .completed)
        #expect(await iterator.next() == nil)
        #expect(await store.job(for: jobId) == nil)
    }

    @Test("events(forJob:) ends with removed when the job is removed externally")
    func perJobStreamEndsOnExternalRemoval() async {
        let jobId = UUID().uuidString
        let store = JobStatusStore.shared

        await store.update(
            with: JobProgress(
                jobId: jobId, jobType: .dialog, status: .running, progress: 0.2, details: nil))

        var iterator = await store.events(forJob: jobId).makeAsyncIterator()
        guard case .updated = await iterator.next() else {
            Issue.record("expected the replayed running state first")
            return
        }

        await store.remove(jobId: jobId)

        guard case .removed = await iterator.next() else {
            Issue.record("expected a removed event after external removal")
            return
        }
        #expect(await iterator.next() == nil)
    }

    @Test("a late progress update does not revive a failed job")
    func lateProgressDoesNotReviveFailedJob() async {
        let jobId = UUID().uuidString
        let store = JobStatusStore.shared

        await store.update(
            with: JobCompletion(
                jobId: jobId, jobType: .dialog, status: .failed, result: "boom", details: nil))
        await store.update(
            with: JobProgress(
                jobId: jobId, jobType: .dialog, status: .running, progress: 0.3, details: nil))

        let info = await store.job(for: jobId)
        #expect(info?.status == .failed)
        #expect(info?.isTerminal == true)
        #expect(info?.result == "boom")

        await store.remove(jobId: jobId)
    }

    @Test("dialog music completion exposes its typed result")
    func dialogMusicCompletionDecodesTypedResult() async throws {
        let jobId = UUID().uuidString
        let store = JobStatusStore.shared
        let result = DialogMusicGenerationResult(
            musicGenerationId: UUID(), mp3Url: "/candidate.mp3", durationSeconds: 8,
            dialogDurationMilliseconds: 5_000, durationExtensionMilliseconds: 3_000,
            requestedMusicLengthMilliseconds: 8_000, prompt: "Warm strings")
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)

        await store.update(
            with: JobCompletion(
                jobId: jobId, jobType: .dialogMusic, status: .completed, result: encoded,
                details: nil))

        let info = await store.job(for: jobId)
        #expect(info?.dialogMusicResult == result)
        await store.remove(jobId: jobId)
    }

    @Test("dialog SwiftData model preserves accepted music")
    func dialogModelPreservesAcceptedMusic() {
        let music = DialogBackgroundMusic(
            soundFile: "dialog/music/scene.wav", generationId: UUID(), prompt: "Warm strings",
            acceptedAt: 1_748_579_999_000)
        let dto = DialogScript(
            id: UUID(), title: "Scene", notes: "",
            turns: [DialogScriptTurn(creatureId: "beaky", text: "Hello")],
            backgroundMusic: music)

        let model = DialogScriptModel(dto: dto)
        let roundTripped = model.toDTO()

        #expect(model.hasBackgroundMusic)
        #expect(roundTripped.id == dto.id)
        #expect(roundTripped.title == dto.title)
        #expect(roundTripped.turns.map(\.creatureId) == dto.turns.map(\.creatureId))
        #expect(roundTripped.turns.map(\.text) == dto.turns.map(\.text))
        #expect(roundTripped.backgroundMusic == music)
    }
}
