import Foundation

extension StoryboardAction {

    /// What's missing before this action can actually run, or `nil` if it's fully configured.
    ///
    /// The editor uses this to block saving tiles that would fail at perform time — mid-show is
    /// the worst possible moment to discover an empty id. Phrased to follow "Tile “X” …".
    public var configurationProblem: String? {
        switch self {
        case .playAnimation(let animationId, _, _, _):
            return animationId.isEmpty ? "needs an animation selected" : nil
        case .adHocSpeech(let creatureId, _), .liveControl(let creatureId, _):
            return creatureId.isEmpty ? "needs a creature selected" : nil
        case .startPlaylist(let playlistId, _):
            return playlistId.isEmpty ? "needs a playlist selected" : nil
        case .stopPlaylist:
            return nil
        case .playSound(let fileName):
            return fileName.isEmpty ? "needs a sound selected" : nil
        case .renderDialog:
            // Script ids are structurally valid UUIDs; existence is the server's call.
            return nil
        case .fixtureOn(let fixtureId), .fixtureOff(let fixtureId), .fixtureDetails(let fixtureId):
            return fixtureId.isEmpty ? "needs a fixture selected" : nil
        case .fixturePattern(let fixtureId, let patternId, _):
            if fixtureId.isEmpty { return "needs a fixture selected" }
            if patternId.isEmpty { return "needs a pattern selected" }
            return nil
        case .unknown(let type, _):
            // An empty type is the editor's "no action assigned yet" placeholder; a non-empty
            // one is a future action from a newer client and presumed valid.
            return type.isEmpty ? "needs an action assigned" : nil
        }
    }
}
