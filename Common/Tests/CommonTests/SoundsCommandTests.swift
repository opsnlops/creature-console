import ArgumentParser
import Foundation
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
        private(set) var adHocListCallCount = 0
        private(set) var adHocURLRequests: [String] = []
        private(set) var soundURLRequests: [String] = []

        var listResult: Result<[Sound], ServerError>
        var playResult: Result<String, ServerError>
        var generateResult: Result<JobCreatedResponse, ServerError>
        var adHocListResult: Result<[AdHocSoundEntry], ServerError>
        var adHocURLResult: Result<URL, ServerError>
        var soundURLResult: Result<URL, ServerError>

        init(
            listResult: Result<[Sound], ServerError> = .success([]),
            playResult: Result<String, ServerError> = .success("Played"),
            generateResult: Result<JobCreatedResponse, ServerError> = .success(
                JobCreatedResponse(jobId: "job-123", jobType: .lipSync, message: "queued")
            ),
            adHocListResult: Result<[AdHocSoundEntry], ServerError> = .success([]),
            adHocURLResult: Result<URL, ServerError> = .success(
                URL(string: "https://example.com/sound.wav")!),
            soundURLResult: Result<URL, ServerError> = .success(
                URL(string: "https://example.com/download.wav")!)
        ) {
            self.listResult = listResult
            self.playResult = playResult
            self.generateResult = generateResult
            self.adHocListResult = adHocListResult
            self.adHocURLResult = adHocURLResult
            self.soundURLResult = soundURLResult
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
            JobCreatedResponse, ServerError
        > {
            generateCalls.append(GenerateCall(fileName: fileName, overwrite: allowOverwrite))
            return generateResult
        }

        func listAdHocSounds() async -> Result<[AdHocSoundEntry], ServerError> {
            adHocListCallCount += 1
            return adHocListResult
        }

        func adHocSoundURL(for fileName: String) async -> Result<URL, ServerError> {
            adHocURLRequests.append(fileName)
            return adHocURLResult
        }

        func soundURL(for fileName: String) async -> Result<URL, ServerError> {
            soundURLRequests.append(fileName)
            return soundURLResult
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

        func recordedAdHocListCount() async -> Int {
            adHocListCallCount
        }

        func recordedAdHocURLRequests() async -> [String] {
            adHocURLRequests
        }

        func recordedSoundURLRequests() async -> [String] {
            soundURLRequests
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

    private func makeDownloadCommand(
        fileName: String, output: String? = nil, overwrite: Bool = false
    ) -> CreatureCLI.Sounds.Download {
        var command = CreatureCLI.Sounds.Download()
        command.fileName = fileName
        command.output = output
        command.overwrite = overwrite
        command.globalOptions = GlobalOptions()
        return command
    }

    private func makeAdHocListCommand() -> CreatureCLI.Sounds.AdHoc.List {
        var command = CreatureCLI.Sounds.AdHoc.List()
        command.globalOptions = GlobalOptions()
        return command
    }

    private func makeAdHocDownloadCommand(
        soundPath: String, output: String? = nil, overwrite: Bool = false
    ) -> CreatureCLI.Sounds.AdHoc.Download {
        var command = CreatureCLI.Sounds.AdHoc.Download()
        command.soundFilePath = soundPath
        command.output = output
        command.overwrite = overwrite
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
        let stub = StubSoundServer(
            generateResult: .success(
                JobCreatedResponse(jobId: "job-1", jobType: .lipSync, message: "queued")
            )
        )
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

    @Test("download command refuses to overwrite without flag")
    func downloadCommandRejectsExistingDestination() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destination = tempDir.appendingPathComponent("tone.wav")
        FileManager.default.createFile(atPath: destination.path, contents: Data("old".utf8))

        let stub = StubSoundServer()
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeDownloadCommand(fileName: "tone.wav", output: destination.path)
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let requests = await stub.recordedSoundURLRequests()
        #expect(requests.isEmpty)

        try? FileManager.default.removeItem(at: tempDir)
        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("download command uses server URL and download handler")
    func downloadCommandUsesServerHandler() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destination = tempDir.appendingPathComponent("tone.wav")

        let remoteURL = URL(string: "https://example.com/normal/tone.wav")!
        let stub = StubSoundServer(soundURLResult: .success(remoteURL))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        await SoundDownloadHandlerStore.shared.updateHandler { _, destination in
            try Data("normal audio".utf8).write(to: destination)
            return destination
        }

        let command = makeDownloadCommand(fileName: "tone.wav", output: destination.path)
        try await command.run()

        let requests = await stub.recordedSoundURLRequests()
        #expect(requests == ["tone.wav"])

        let contents = try Data(contentsOf: destination)
        #expect(String(decoding: contents, as: UTF8.self) == "normal audio")

        await SoundDownloadHandlerStore.shared.resetHandler()
        try? FileManager.default.removeItem(at: tempDir)
        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("download command surfaces server errors")
    func downloadCommandSurfacesServerErrors() async {
        let stub = StubSoundServer(soundURLResult: .failure(.serverError("nope")))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeDownloadCommand(fileName: "tone.wav")
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let requests = await stub.recordedSoundURLRequests()
        #expect(requests == ["tone.wav"])

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("ad-hoc list command delegates to server")
    func adHocListCommandDelegatesToServer() async throws {
        let entry = AdHocSoundEntry(
            animationId: "anim-1",
            createdAt: Date(timeIntervalSince1970: 0),
            soundFilePath: "ad-hoc/anim-1.wav",
            sound: Sound(fileName: "anim-1.wav", size: 2_048)
        )
        let stub = StubSoundServer(adHocListResult: .success([entry]))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeAdHocListCommand()
        try await command.run()

        let listCount = await stub.recordedAdHocListCount()
        #expect(listCount == 1)

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("ad-hoc list command surfaces server errors")
    func adHocListCommandSurfacesErrors() async {
        let stub = StubSoundServer(adHocListResult: .failure(.serverError("nope")))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeAdHocListCommand()
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let listCount = await stub.recordedAdHocListCount()
        #expect(listCount == 1)

        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("ad-hoc download refuses to overwrite without flag")
    func adHocDownloadRejectsExistingDestination() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destination = tempDir.appendingPathComponent("anim.wav")
        FileManager.default.createFile(atPath: destination.path, contents: Data("old".utf8))

        let stub = StubSoundServer()
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        let command = makeAdHocDownloadCommand(
            soundPath: "ad-hoc/anim.wav", output: destination.path, overwrite: false)
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let urlRequests = await stub.recordedAdHocURLRequests()
        #expect(urlRequests.isEmpty)

        try? FileManager.default.removeItem(at: tempDir)
        await CreatureCLI.Sounds.resetServerFactory()
    }

    @Test("ad-hoc download uses server URL and download handler")
    func adHocDownloadUsesServerHandler() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destination = tempDir.appendingPathComponent("anim.wav")

        let remoteURL = URL(string: "https://example.com/ad-hoc/anim.wav")!
        let stub = StubSoundServer(adHocURLResult: .success(remoteURL))
        await CreatureCLI.Sounds.useServerFactory { _ in stub }

        await SoundDownloadHandlerStore.shared.updateHandler { _, destination in
            try Data("new audio".utf8).write(to: destination)
            return destination
        }

        let command = makeAdHocDownloadCommand(
            soundPath: "ad-hoc/anim.wav", output: destination.path, overwrite: false)
        try await command.run()

        let requests = await stub.recordedAdHocURLRequests()
        #expect(requests == ["ad-hoc/anim.wav"])
        let contents = try Data(contentsOf: destination)
        #expect(String(decoding: contents, as: UTF8.self) == "new audio")

        await SoundDownloadHandlerStore.shared.resetHandler()
        try? FileManager.default.removeItem(at: tempDir)
        await CreatureCLI.Sounds.resetServerFactory()
    }
}
