import ArgumentParser
import Foundation
import Testing

@testable import Common
@testable import creature_cli

@Suite(.serialized)
struct AnimationsAdHocCommandTests {

    actor StubAdHocAnimationServer: AdHocAnimationCommandClient {
        private(set) var listCallCount = 0
        private(set) var requestedIds: [AnimationIdentifier] = []

        var listResult: Result<[AdHocAnimationSummary], ServerError>
        var getResult: Result<Animation, ServerError>

        init(
            listResult: Result<[AdHocAnimationSummary], ServerError> = .success([]),
            getResult: Result<Animation, ServerError> = .success(Common.Animation.mock())
        ) {
            self.listResult = listResult
            self.getResult = getResult
        }

        func listAdHocAnimations() async -> Result<[AdHocAnimationSummary], ServerError> {
            listCallCount += 1
            return listResult
        }

        func getAdHocAnimation(animationId: AnimationIdentifier) async -> Result<
            Animation, ServerError
        > {
            requestedIds.append(animationId)
            return getResult
        }

        func recordedListCount() async -> Int { listCallCount }
        func recordedRequestedIds() async -> [AnimationIdentifier] { requestedIds }
    }

    private func makeListCommand() -> CreatureCLI.Animations.AdHoc.List {
        var command = CreatureCLI.Animations.AdHoc.List()
        command.globalOptions = GlobalOptions()
        return command
    }

    private func makeShowCommand(id: AnimationIdentifier) -> CreatureCLI.Animations.AdHoc.Show {
        var command = CreatureCLI.Animations.AdHoc.Show()
        command.animationId = id
        command.globalOptions = GlobalOptions()
        return command
    }

    private func sampleSummary() -> AdHocAnimationSummary {
        let metadata = AnimationMetadata(
            id: "anim-123",
            title: "Crowd work riff",
            lastUpdated: Date(),
            millisecondsPerFrame: 20,
            note: "",
            soundFile: "anim-123.wav",
            numberOfFrames: 480,
            multitrackAudio: false
        )
        return AdHocAnimationSummary(
            animationId: metadata.id, metadata: metadata, createdAt: Date())
    }

    @Test("ad-hoc animation list delegates to server")
    func adHocAnimationListDelegates() async throws {
        let summary = sampleSummary()
        let stub = StubAdHocAnimationServer(listResult: .success([summary]))
        await CreatureCLI.Animations.AdHoc.useServerFactory { _ in stub }

        let command = makeListCommand()
        try await command.run()

        let count = await stub.recordedListCount()
        #expect(count == 1)

        await CreatureCLI.Animations.AdHoc.resetServerFactory()
    }

    @Test("ad-hoc animation list surfaces server errors")
    func adHocAnimationListSurfacesErrors() async {
        let stub = StubAdHocAnimationServer(listResult: .failure(.serverError("nope")))
        await CreatureCLI.Animations.AdHoc.useServerFactory { _ in stub }

        let command = makeListCommand()
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let count = await stub.recordedListCount()
        #expect(count == 1)

        await CreatureCLI.Animations.AdHoc.resetServerFactory()
    }

    @Test("ad-hoc animation show requests the provided id")
    func adHocAnimationShowRequestsId() async throws {
        let animation = Common.Animation.mock()
        let stub = StubAdHocAnimationServer(getResult: .success(animation))
        await CreatureCLI.Animations.AdHoc.useServerFactory { _ in stub }

        let command = makeShowCommand(id: animation.metadata.id)
        try await command.run()

        let requested = await stub.recordedRequestedIds()
        #expect(requested == [animation.metadata.id])

        await CreatureCLI.Animations.AdHoc.resetServerFactory()
    }

    @Test("ad-hoc animation show surfaces server errors")
    func adHocAnimationShowSurfacesErrors() async {
        let stub = StubAdHocAnimationServer(getResult: .failure(.serverError("boom")))
        await CreatureCLI.Animations.AdHoc.useServerFactory { _ in stub }

        let command = makeShowCommand(id: "anim-404")
        let thrown = await #expect(throws: ExitCode.self) {
            try await command.run()
        }
        #expect(thrown == .failure)

        let requested = await stub.recordedRequestedIds()
        #expect(requested == ["anim-404"])

        await CreatureCLI.Animations.AdHoc.resetServerFactory()
    }
}
