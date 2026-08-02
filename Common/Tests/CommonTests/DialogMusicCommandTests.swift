import ArgumentParser
import Foundation
import Testing

@testable import Common
@testable import creature_cli

@Suite(.serialized)
struct DialogMusicCommandTests {
    actor StubServer: DialogMusicCommandClient {
        private(set) var requests: [DialogMusicRequest] = []
        private(set) var promotedIds: [UUID] = []
        private(set) var downloadedURLs: [URL] = []

        let script: DialogScript
        let previewMeta: DialogPreviewMetaDTO
        let generationResult: DialogMusicGenerationResult
        var downloadedData = Data("mp3".utf8)

        init() throws {
            script = DialogScript(
                id: UUID(), title: "Test Scene", notes: "",
                turns: [DialogScriptTurn(creatureId: "beaky", text: "Hello")])
            previewMeta = try JSONDecoder().decode(
                DialogPreviewMetaDTO.self,
                from: Data(
                    """
                    {
                      "cache_key": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                      "generation_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
                      "audio_url": "/api/v1/animation/dialog/preview/audio/a/take.wav",
                      "duration_seconds": 2.5
                    }
                    """.utf8))
            generationResult = DialogMusicGenerationResult(
                musicGenerationId: UUID(), mp3Url: "/candidate.mp3", durationSeconds: 5,
                dialogDurationMilliseconds: 2_500, durationExtensionMilliseconds: 2_500,
                requestedMusicLengthMilliseconds: 5_000, prompt: "Warm strings")
        }

        func getDialogScript(id: DialogScriptIdentifier) async -> Result<DialogScript, ServerError>
        {
            .success(script)
        }

        func dialogPreviewMeta(_ request: DialogPreviewRequest) async -> Result<
            CreatureServerClient.DialogPreviewMetaOutcome, ServerError
        > {
            .success(.meta(previewMeta))
        }

        func generateDialogMusic(_ request: DialogMusicRequest) async -> Result<
            JobCreatedResponse, ServerError
        > {
            requests.append(request)
            return .success(
                JobCreatedResponse(jobId: "music-job", jobType: .dialogMusic, message: "queued"))
        }

        func getJob(jobId: String) async -> Result<JobStateSnapshot, ServerError> {
            do {
                let encoded = String(
                    decoding: try JSONEncoder().encode(generationResult), as: UTF8.self)
                return .success(
                    JobStateSnapshot(
                        jobId: jobId, jobType: .dialogMusic, status: .completed, progress: 1,
                        result: encoded, details: nil))
            } catch {
                return .failure(.dataFormatError(error.localizedDescription))
            }
        }

        func promoteDialogMusic(generationId: UUID) async -> Result<
            DialogMusicPromotionResult, ServerError
        > {
            promotedIds.append(generationId)
            return .success(
                DialogMusicPromotionResult(
                    musicGenerationId: generationId, soundFile: "dialog/music/test.wav",
                    mp3Url: "/accepted.mp3"))
        }

        func musicCandidateURL(generationId: UUID) async -> Result<URL, ServerError> {
            .success(URL(string: "https://example.test/\(generationId).mp3")!)
        }

        func downloadRawData(from url: URL) async -> Result<Data, ServerError> {
            downloadedURLs.append(url)
            return .success(downloadedData)
        }

        func recordedRequests() -> [DialogMusicRequest] { requests }
        func recordedPromotions() -> [UUID] { promotedIds }
    }

    @Test("generate resolves a full voice take and forwards music options")
    func generateForwardsOptions() async throws {
        let stub = try StubServer()
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }

        let script = stub.script
        let meta = stub.previewMeta
        var command = CreatureCLI.Dialog.Music.Generate()
        command.scriptId = script.id.uuidString
        command.dialogGenerationId = nil
        command.prompt = "Warm strings"
        command.durationExtensionMs = 2_500
        command.mode = .ambience
        command.output = nil
        command.overwrite = false
        command.globalOptions = GlobalOptions()
        try await command.run()
        await CreatureCLI.Dialog.Music.resetServerFactory()

        let request = try #require(await stub.recordedRequests().first)
        #expect(request.scriptId == script.id)
        #expect(request.dialogGenerationId == meta.generationId)
        #expect(request.durationExtensionMilliseconds == 2_500)
        #expect(request.generationMode == .ambience)
    }

    @Test("download requires an MP3 destination before contacting the server")
    func downloadRejectsNonMP3() async throws {
        let stub = try StubServer()
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }

        var command = CreatureCLI.Dialog.Music.Download()
        command.generationId = UUID().uuidString
        command.output = "/tmp/candidate.wav"
        command.overwrite = false
        command.globalOptions = GlobalOptions()
        let error = await #expect(throws: ExitCode.self) { try await command.run() }
        #expect(error == .failure)

        await CreatureCLI.Dialog.Music.resetServerFactory()
    }

    @Test("promote accepts the requested generation")
    func promoteForwardsGeneration() async throws {
        let stub = try StubServer()
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }
        let generationId = UUID()

        var command = CreatureCLI.Dialog.Music.Promote()
        command.generationId = generationId.uuidString
        command.globalOptions = GlobalOptions()
        try await command.run()

        #expect(await stub.recordedPromotions() == [generationId])
        await CreatureCLI.Dialog.Music.resetServerFactory()
    }
}
