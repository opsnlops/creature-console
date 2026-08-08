import Common
import Foundation

/// The bits of a creature a stage cares about: who they are, what to call them, and which audio
/// lane they speak on.
///
/// Kept separate from `Common.Creature` so the stage editor can be driven from a SwiftData query,
/// a server fetch, or a preview without dragging the full creature record around.
struct StageCreature: Equatable, Identifiable, Sendable {
    let id: CreatureIdentifier
    let name: String
    let audioChannel: Int

    /// Whether this creature can be placed at all. Lanes 1–16 carry creatures; lane 17 is
    /// background music, and anything outside that range has no audio to position.
    var hasPlayableAudioLane: Bool {
        (1...16).contains(audioChannel)
    }
}

extension StageCreature {
    init(_ creature: Creature) {
        self.init(id: creature.id, name: creature.name, audioChannel: creature.audioChannel)
    }
}
