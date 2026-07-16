import Foundation
import Testing

@testable import Common

@Suite("StoryboardAction configuration validation")
struct StoryboardActionValidationTests {

    @Test("fully configured actions have no problem")
    func fullyConfiguredActionsPass() {
        let configured: [StoryboardAction] = [
            .playAnimation(
                animationId: "abc123", universe: 1, interrupt: true, resumePlaylist: true),
            .adHocSpeech(creatureId: "creature-1", resumePlaylist: true),
            .liveControl(creatureId: "creature-1", universe: nil),
            .startPlaylist(playlistId: "playlist-1", universe: nil),
            .stopPlaylist(universe: nil),
            .playSound(fileName: "beep.wav"),
            .renderDialog(scriptId: UUID()),
            .fixtureOn(fixtureId: "fixture-1"),
            .fixtureOff(fixtureId: "fixture-1"),
            .fixturePattern(fixtureId: "fixture-1", patternId: "pattern-1", stopAfterMs: nil),
            .fixtureDetails(fixtureId: "fixture-1"),
        ]
        for action in configured {
            #expect(action.configurationProblem == nil, "unexpected problem for \(action.typeName)")
        }
    }

    @Test("empty ids are flagged with a human-readable problem")
    func emptyIdsAreFlagged() {
        let incomplete: [(StoryboardAction, String)] = [
            (
                .playAnimation(
                    animationId: "", universe: nil, interrupt: false, resumePlaylist: true),
                "needs an animation selected"
            ),
            (.adHocSpeech(creatureId: "", resumePlaylist: true), "needs a creature selected"),
            (.liveControl(creatureId: "", universe: 2), "needs a creature selected"),
            (.startPlaylist(playlistId: "", universe: nil), "needs a playlist selected"),
            (.playSound(fileName: ""), "needs a sound selected"),
            (.fixtureOn(fixtureId: ""), "needs a fixture selected"),
            (.fixtureOff(fixtureId: ""), "needs a fixture selected"),
            (.fixtureDetails(fixtureId: ""), "needs a fixture selected"),
        ]
        for (action, expected) in incomplete {
            #expect(action.configurationProblem == expected)
        }
    }

    @Test("fixture pattern reports the fixture before the pattern")
    func fixturePatternProblemOrder() {
        #expect(
            StoryboardAction.fixturePattern(fixtureId: "", patternId: "", stopAfterMs: nil)
                .configurationProblem == "needs a fixture selected")
        #expect(
            StoryboardAction.fixturePattern(fixtureId: "f-1", patternId: "", stopAfterMs: 500)
                .configurationProblem == "needs a pattern selected")
    }

    @Test("unknown actions: empty type is unassigned, future type is presumed valid")
    func unknownActions() {
        #expect(
            StoryboardAction.unknown(type: "", raw: [:]).configurationProblem
                == "needs an action assigned")
        #expect(
            StoryboardAction.unknown(type: "hologram_mode", raw: ["type": .string("hologram_mode")])
                .configurationProblem == nil)
    }
}
