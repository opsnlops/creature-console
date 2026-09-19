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

        private(set) var planRequests: [DialogMusicPlanRequest] = []
        var recipe: DialogMusicRecipe?

        func draftDialogMusicPlan(_ request: DialogMusicPlanRequest) async -> Result<
            DialogMusicPlanResult, ServerError
        > {
            planRequests.append(request)
            return .success(
                DialogMusicPlanResult(
                    modelId: request.modelId.rawValue, musicLengthMilliseconds: 5_000,
                    dialogDurationMilliseconds: 2_500,
                    durationExtensionMilliseconds: request.durationExtensionMilliseconds,
                    compositionPlan: MusicCompositionPlan(chunks: [
                        .generation(
                            MusicGenerationChunk(
                                text: "[Intro] \(request.prompt)", durationMilliseconds: 5_000))
                    ])))
        }

        func getDialogMusicRecipe(generationId: UUID) async -> Result<
            DialogMusicRecipe, ServerError
        > {
            guard let recipe else { return .failure(.notFound("no such candidate")) }
            return .success(recipe)
        }

        func listMusicFinetunes() async -> Result<MusicFinetuneList, ServerError> {
            .success(MusicFinetuneList(count: 0, items: []))
        }

        func setRecipe(_ value: DialogMusicRecipe?) { recipe = value }
        func recordedRequests() -> [DialogMusicRequest] { requests }
        func recordedPlanRequests() -> [DialogMusicPlanRequest] { planRequests }
        func recordedPromotions() -> [UUID] { promotedIds }
    }

    private func makeGenerate(scriptId: UUID) -> CreatureCLI.Dialog.Music.Generate {
        var command = CreatureCLI.Dialog.Music.Generate()
        command.scriptId = scriptId.uuidString
        command.dialogGenerationId = nil
        command.prompt = nil
        command.durationExtensionMs = 0
        command.mode = .track
        command.allowVocals = false
        command.plan = nil
        command.seed = nil
        command.finetune = nil
        command.finetuneStrength = nil
        command.storeForInpainting = true
        command.output = nil
        command.overwrite = false
        command.globalOptions = GlobalOptions()
        return command
    }

    private func writePlanFile(_ plan: MusicCompositionPlan) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-\(UUID().uuidString).json")
        try JSONEncoder().encode(plan).write(to: url)
        return url.path
    }

    @Test("generate resolves a full voice take and forwards music options")
    func generateForwardsOptions() async throws {
        let stub = try StubServer()
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }

        let script = stub.script
        let meta = stub.previewMeta
        var command = makeGenerate(scriptId: script.id)
        command.prompt = "Warm strings"
        command.durationExtensionMs = 2_500
        command.mode = .ambience
        command.allowVocals = true
        command.finetune = "ft-1"
        command.finetuneStrength = 1.5
        try await command.run()
        await CreatureCLI.Dialog.Music.resetServerFactory()

        let request = try #require(await stub.recordedRequests().first)
        #expect(request.scriptId == script.id)
        #expect(request.dialogGenerationId == meta.generationId)
        #expect(request.durationExtensionMilliseconds == 2_500)
        #expect(request.generationMode == .ambience)
        #expect(request.modelId == .v2_5)
        #expect(request.finetune == MusicFinetuneSelection(finetuneId: "ft-1", strength: 1.5))
        guard case .prompt(let prompt) = request.composition else {
            Issue.record("expected a prompt-mode request")
            return
        }
        #expect(prompt.forceInstrumental == false)
    }

    @Test("generate sends a plan file as a plan-mode request with its seed")
    func generateForwardsPlan() async throws {
        let stub = try StubServer()
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }

        let plan = MusicCompositionPlan(chunks: [
            .generation(MusicGenerationChunk(text: "[Intro]", durationMilliseconds: 5_000))
        ])
        var command = makeGenerate(scriptId: stub.script.id)
        command.plan = try writePlanFile(plan)
        command.seed = 77
        try await command.run()
        await CreatureCLI.Dialog.Music.resetServerFactory()

        let request = try #require(await stub.recordedRequests().first)
        #expect(request.compositionPlan == plan)
        #expect(request.seed == 77)
        #expect(request.prompt == nil)
    }

    @Test("generate refuses a plan the server would reject before sending it")
    func generateRejectsShortPlan() async throws {
        let stub = try StubServer()
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }

        // A 2 s section is under the 3 s minimum: the client-side check must stop it here.
        let plan = MusicCompositionPlan(chunks: [
            .generation(MusicGenerationChunk(text: "x", durationMilliseconds: 2_000))
        ])
        var command = makeGenerate(scriptId: stub.script.id)
        command.plan = try writePlanFile(plan)
        let error = await #expect(throws: ExitCode.self) { try await command.run() }
        #expect(error == .failure)
        #expect(await stub.recordedRequests().isEmpty)

        await CreatureCLI.Dialog.Music.resetServerFactory()
    }

    @Test("generate needs exactly one of --prompt and --plan, and --seed only with --plan")
    func generateModeExclusivity() async throws {
        let stub = try StubServer()
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }

        var neither = makeGenerate(scriptId: stub.script.id)
        neither.prompt = nil
        #expect(await #expect(throws: ExitCode.self) { try await neither.run() } == .failure)

        var both = makeGenerate(scriptId: stub.script.id)
        both.prompt = "x"
        both.plan = "/tmp/never-read.json"
        #expect(await #expect(throws: ExitCode.self) { try await both.run() } == .failure)

        var seededPrompt = makeGenerate(scriptId: stub.script.id)
        seededPrompt.prompt = "x"
        seededPrompt.seed = 1
        #expect(await #expect(throws: ExitCode.self) { try await seededPrompt.run() } == .failure)

        #expect(await stub.recordedRequests().isEmpty)
        await CreatureCLI.Dialog.Music.resetServerFactory()
    }

    @Test("plan drafts against the resolved take and writes the plan JSON")
    func planWritesDraft() async throws {
        let stub = try StubServer()
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-\(UUID().uuidString).json").path
        var command = CreatureCLI.Dialog.Music.Plan()
        command.scriptId = stub.script.id.uuidString
        command.dialogGenerationId = nil
        command.prompt = "Bright pizzicato"
        command.durationExtensionMs = 1_000
        command.sourcePlan = nil
        command.output = output
        command.overwrite = false
        command.globalOptions = GlobalOptions()
        try await command.run()
        await CreatureCLI.Dialog.Music.resetServerFactory()

        let request = try #require(await stub.recordedPlanRequests().first)
        #expect(request.dialogGenerationId == stub.previewMeta.generationId)
        #expect(request.prompt == "Bright pizzicato")
        #expect(request.durationExtensionMilliseconds == 1_000)
        let written = try JSONDecoder().decode(
            MusicCompositionPlan.self, from: Data(contentsOf: URL(fileURLWithPath: output)))
        #expect(written.chunks.count == 1)
    }

    @Test("recipe reports an expired candidate as a failure")
    func recipeExpired() async throws {
        let stub = try StubServer()
        await stub.setRecipe(nil)
        await CreatureCLI.Dialog.Music.useServerFactory { _ in stub }

        var command = CreatureCLI.Dialog.Music.Recipe()
        command.generationId = UUID().uuidString
        command.output = nil
        command.overwrite = false
        command.globalOptions = GlobalOptions()
        let error = await #expect(throws: ExitCode.self) { try await command.run() }
        #expect(error == .failure)

        await CreatureCLI.Dialog.Music.resetServerFactory()
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
