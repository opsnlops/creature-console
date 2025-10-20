import ArgumentParser
import Testing

@testable import Common
@testable import creature_cli

@Suite(.serialized)
struct SoundsCommandTests {

    actor StubSoundServer: SoundCommandClient {
        struct GenerateCall: Equatable, Sendable {
            let fileName: String
            let overwrite: Bool
        }

        struct PlayCall: Equatable, Sendable {
            let fileName: String
        }

        private(set) var generateCalls: [GenerateCall] = []
        private(set) var playCalls: [PlayCall] = []
        private(set) var listCallCount = 0

        var listResult: Result<[Sound], ServerError>
        var playResult: Result<String, ServerError>
        var generateResult: Result<String, ServerError>

        init(
            listResult: Result<[Sound], ServerError> = .success([]),
            playResult: Result<String, ServerError> = .success("Played"),
            generateResult: Result<String, ServerError> = .success("Generated")
        ) {
            self.listResult = listResult
            self.playResult = playResult
            self.generateResult = generateResult
        }

        func listSounds() async -> Result<[Sound], ServerError> {
            listCallCount += 1
            return listResult
        }

        func playSound(_ fileName: String) async -> Result<String, ServerError> {
            playCalls.append(PlayCall(fileName: fileName))
            return playResult
        }

        func generateLipSync(for fileName: String, allowOverwrite: Bool) async -> Result<
            String, ServerError
        > {
            generateCalls.append(GenerateCall(fileName: fileName, overwrite: allowOverwrite))
            return generateResult
        }

        func recordedGenerateCalls() async -> [GenerateCall] {
            generateCalls
        }

        func recordedPlayCalls() async -> [PlayCall] {
            playCalls
        }

        func recordedListCount() async -> Int {
            listCallCount
        }
    }

    private func makeGenerateCommand(fileName: String, overwrite: Bool = false)
        -> CreatureCLI.Sounds.GenerateLipSync
    {
        var command = CreatureCLI.Sounds.GenerateLipSync()
        command.fileName = fileName
        command.overwrite = overwrite
        command.globalOptions = GlobalOptions()
        return command
    }

    private func makeListCommand() -> CreatureCLI.Sounds.List {
        var command = CreatureCLI.Sounds.List()
        command.globalOptions = GlobalOptions()
        return command
    }

    private func makePlayCommand(fileName: String) -> CreatureCLI.Sounds.Play {
        var command = CreatureCLI.Sounds.Play()
        command.fileName = fileName
        command.globalOptions = GlobalOptions()
        return command
    }

    @Test("rejects non-WAV files before contacting server")
    func rejectsNonWavFiles() async {
        let stub = StubSoundServer()
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeGenerateCommand(fileName: "voice.mp3")
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let generateCalls = await stub.recordedGenerateCalls()
        #expect(generateCalls.isEmpty)
        let playCalls = await stub.recordedPlayCalls()
        #expect(playCalls.isEmpty)
        let listCount = await stub.recordedListCount()
        #expect(listCount == 0)

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("invokes server with overwrite flag")
    func invokesServerWithOverwriteFlag() async throws {
        let stub = StubSoundServer(generateResult: .success("ok"))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeGenerateCommand(fileName: "voice.wav", overwrite: true)
        try await command.run()

        let generateCalls = await stub.recordedGenerateCalls()
        #expect(generateCalls == [.init(fileName: "voice.wav", overwrite: true)])

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("propagates server errors as exit codes")
    func propagatesServerErrors() async {
        let stub = StubSoundServer(generateResult: .failure(.serverError("boom")))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeGenerateCommand(fileName: "voice.wav")
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let generateCalls = await stub.recordedGenerateCalls()
        #expect(generateCalls == [.init(fileName: "voice.wav", overwrite: false)])

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("list command delegates to server")
    func listCommandDelegatesToServer() async throws {
        let sounds = [Sound(fileName: "tone.wav", size: 1_024)]
        let stub = StubSoundServer(listResult: .success(sounds))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeListCommand()
        try await command.run()

        let listCount = await stub.recordedListCount()
        #expect(listCount == 1)
        let playCalls = await stub.recordedPlayCalls()
        #expect(playCalls.isEmpty)
        let generateCalls = await stub.recordedGenerateCalls()
        #expect(generateCalls.isEmpty)

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("list command surfaces server errors")
    func listCommandSurfacesServerErrors() async {
        let stub = StubSoundServer(listResult: .failure(.serverError("nope")))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeListCommand()
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let listCount = await stub.recordedListCount()
        #expect(listCount == 1)

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("play command delegates to server")
    func playCommandDelegatesToServer() async throws {
        let stub = StubSoundServer(playResult: .success("ok"))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makePlayCommand(fileName: "tone.wav")
        try await command.run()

        let playCalls = await stub.recordedPlayCalls()
        #expect(playCalls == [.init(fileName: "tone.wav")])

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("play command surfaces server errors")
    func playCommandSurfacesServerErrors() async {
        let stub = StubSoundServer(playResult: .failure(.serverError("boom")))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makePlayCommand(fileName: "tone.wav")
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let playCalls = await stub.recordedPlayCalls()
        #expect(playCalls == [.init(fileName: "tone.wav")])

        await CreatureCLI.Sounds.resetServerFactory()
    }
}
