import Common
import SwiftData
import SwiftUI

/// Binds a dialog scene to a stage — the physical arrangement it's normally rendered against.
///
/// Bind one and the server turns each creature's head toward whoever is speaking (with the
/// per-creature reaction delays from issue #119); leave it unbound and the render is byte-identical
/// to a pre-stage render. The picker is backed by the SwiftData stage mirror, so a stage created or
/// renamed on another device shows up here on its own.
///
/// The map is the same canvas the stage editor uses, read-only, with the scene's speakers called
/// out — the point is to answer "will this cast actually look at each other?" before spending an
/// ElevenLabs render finding out.
struct StageBindingPanel: View {

    /// The script's stage binding, edited in place and saved with the script.
    @Binding var stageId: StageIdentifier?

    /// The creatures with lines in this scene, in speaking order.
    let speakingCreatureIDs: [CreatureIdentifier]

    /// Resolves a creature id to a display name for the warning text.
    let creatureName: (CreatureIdentifier) -> String

    @Query(sort: \StageModel.title) private var stageModels: [StageModel]
    @Query(sort: \CreatureModel.name) private var creatures: [CreatureModel]

    private var boundStage: Stage? {
        guard let stageId else { return nil }
        return stageModels.first(where: { $0.id == stageId })?.toDTO()
    }

    /// Speakers in the scene who have no placement on the bound stage. The server renders them
    /// fine — they just won't be looked at, and won't look at anyone, which on hardware is
    /// indistinguishable from a bug.
    private var unplacedSpeakers: [CreatureIdentifier] {
        guard let boundStage else { return [] }
        let placed = Set(boundStage.placements.map(\.creatureID))
        var seen = Set<CreatureIdentifier>()
        return speakingCreatureIDs.filter { id in
            !id.isEmpty && !placed.contains(id) && seen.insert(id).inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stage").font(.title2.bold())

            Picker("Stage", selection: $stageId) {
                Text("None — no head aiming").tag(StageIdentifier?.none)
                ForEach(stageModels) { model in
                    Text(model.title.isEmpty ? "(untitled)" : model.title)
                        .tag(Optional(model.id))
                }
            }
            .pickerStyle(.menu)

            if let stage = boundStage {
                StageMapView(
                    placements: stage.placements,
                    selectedCreatureID: .constant(nil),
                    displayName: displayName(for:),
                    emphasizedCreatureIDs: Set(speakingCreatureIDs)
                )
                .frame(height: 230)
                .allowsHitTesting(false)

                if unplacedSpeakers.isEmpty {
                    Label(
                        "Everyone with a line is placed. When rendered, the cast will turn toward whoever is speaking.",
                        systemImage: "eyes"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        unplacedSpeakerWarning,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(
                        "Unplaced speakers still render and speak — but nobody turns toward them, and they don't look at anyone. Place them on the stage, or expect them to stare into space."
                    )
                }
            } else if stageModels.isEmpty {
                Label(
                    "No stages exist yet. Create one under Stages in the sidebar to give this scene head aiming.",
                    systemImage: "square.on.square.dashed"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Unbound — this scene renders without head aiming. The cast will speak, but nobody looks at anybody.",
                    systemImage: "eye.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var unplacedSpeakerWarning: String {
        let names = unplacedSpeakers.map(creatureName)
        let list = names.joined(separator: ", ")
        return names.count == 1
            ? "\(list) has lines in this scene but isn't placed on this stage."
            : "\(list) have lines in this scene but aren't placed on this stage."
    }

    /// Live creature names first, the stage's cached copy as fallback — same rule as the editor.
    private func displayName(for placement: StagePlacement) -> String {
        if let live = creatures.first(where: { $0.id == placement.creatureID })?.name,
            !live.isEmpty
        {
            return live
        }
        return placement.creatureName.isEmpty ? placement.creatureID : placement.creatureName
    }
}
