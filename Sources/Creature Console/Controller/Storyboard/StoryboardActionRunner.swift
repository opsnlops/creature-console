import Common
import Foundation
import OSLog

/// Executes a `StoryboardAction` by dispatching to the shared facades / server client. It holds no
/// trigger logic of its own — every capability is the same code path the rest of the app uses.
/// Owned by the perform view (as `@State`); the view supplies a fixture lookup from its cache.
@MainActor
final class StoryboardActionRunner {

    enum RunOutcome {
        case success(String?)
        case failure(String)
        /// Ad-hoc speech with no text yet — the view should show a prompt then re-run with text.
        case needsPrompt(creatureId: CreatureIdentifier)
        /// The view should present the fixture control sheet for this fixture.
        case presentFixtureSheet(DmxFixtureIdentifier)
    }

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "StoryboardActionRunner")
    private let server = CreatureServerClient.shared

    /// Resolve a fixture (with its channels) from the caller's cache. Set by the perform view.
    var fixtureLookup: (DmxFixtureIdentifier) -> DmxFixture? = { _ in nil }

    /// The universe a tile targets — its explicit override, or the active universe.
    private func resolveUniverse(_ explicit: Int?) -> UniverseIdentifier {
        explicit ?? UserDefaults.standard.integer(forKey: "activeUniverse")
    }

    func run(_ action: StoryboardAction, promptText: String? = nil) async -> RunOutcome {
        switch action {

        case .playAnimation(let animationId, let universe, let interrupt, let resumePlaylist):
            let uni = resolveUniverse(universe)
            let result =
                interrupt
                ? await server.interruptWithAnimation(
                    animationId: animationId, universe: uni, resumePlaylist: resumePlaylist)
                : await server.playStoredAnimation(animationId: animationId, universe: uni)
            return outcome(result)

        case .adHocSpeech(let creatureId, let resumePlaylist):
            let text = promptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return .needsPrompt(creatureId: creatureId) }
            return jobOutcome(
                await server.createAdHocSpeechAnimation(
                    creatureId: creatureId, text: text, resumePlaylist: resumePlaylist))

        case .liveControl(let creatureId, let universe):
            // Shared facade — same per-creature toggle the creature detail screen uses. The tile's
            // universe override (if any) rides along; nil follows the active universe.
            let live = await CreatureManager.shared.toggleStreaming(
                to: creatureId, universe: universe)
            return .success(live == nil ? "Live control stopped" : "Live control on")

        case .startPlaylist(let playlistId, let universe):
            return outcome(
                await server.startPlayingPlaylist(
                    universe: resolveUniverse(universe), playlistId: playlistId))

        case .stopPlaylist(let universe):
            return outcome(await server.stopPlayingPlaylist(universe: resolveUniverse(universe)))

        case .playSound(let fileName):
            return outcome(await server.playSound(fileName))

        case .renderDialog(let scriptId):
            let request = DialogRequest.fromScript(scriptId, persistence: .adhoc, autoplay: true)
            return jobOutcome(await server.renderDialog(request))

        case .fixtureOn(let fixtureId):
            guard let fixture = fixtureLookup(fixtureId) else {
                return .failure("Fixture not found in the local cache.")
            }
            return fixtureOutcome(await FixtureControlService.turnOn(fixture, server: server))

        case .fixtureOff(let fixtureId):
            guard let fixture = fixtureLookup(fixtureId) else {
                return .failure("Fixture not found in the local cache.")
            }
            return fixtureOutcome(await FixtureControlService.turnOff(fixture, server: server))

        case .fixturePattern(let fixtureId, let patternId, let stopAfterMs):
            return fixtureOutcome(
                await FixtureControlService.trigger(
                    patternId: patternId, on: fixtureId, stopAfterMs: stopAfterMs, server: server))

        case .fixtureDetails(let fixtureId):
            return .presentFixtureSheet(fixtureId)

        case .unknown(let type, _):
            return .failure(
                "This tile uses an action this version of the app doesn't support (\(type)). Update the app."
            )
        }
    }

    // MARK: - Result → outcome mapping

    private func outcome(_ result: Result<String, ServerError>) -> RunOutcome {
        switch result {
        case .success(let message): return .success(message)
        case .failure(let error): return .failure(ServerError.detailedMessage(from: error))
        }
    }

    private func jobOutcome(_ result: Result<JobCreatedResponse, ServerError>) -> RunOutcome {
        switch result {
        case .success: return .success(nil)
        case .failure(let error): return .failure(ServerError.detailedMessage(from: error))
        }
    }

    private func fixtureOutcome(_ result: Result<DmxFixture, ServerError>) -> RunOutcome {
        switch result {
        case .success: return .success(nil)
        case .failure(let error): return .failure(ServerError.detailedMessage(from: error))
        }
    }
}
