import SwiftUI
import WorldCore

/// The world giving the floor: each scene with what set it off, who holds the floor, what each
/// character said or passed on, why it closed, and how it played.
struct ScenesPanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var selection: SceneID?

    var body: some View {
        List(store.scenes, id: \.sceneID, selection: $selection) { scene in
            SceneRow(scene: scene)
        }
        .onChange(of: selection) { _, sceneID in
            scried = store.scenes.first { $0.sceneID == sceneID }.map(Scried.scene)
        }
        .overlay {
            if store.scenes.isEmpty {
                ContentUnavailableView(
                    "No scenes yet",
                    systemImage: "theatermasks",
                    description: Text(
                        "A scene opens when more than one character could answer. Say something with two birds logged in."
                    )
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.refreshScenes() }
                }
            }
        }
    }
}

struct SceneRow: View {
    let scene: WorldCore.Scene

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(scene.trigger.text)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(scene.state.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .glassEffect(.regular.tint(color.opacity(0.18)), in: .capsule)
            }
            HStack(spacing: 8) {
                Text(scene.regionID.rawValue)
                Text(scene.participants.map(CharacterName.of).joined(separator: " · "))
                Text(scene.openedAt, format: .dateTime.hour().minute().second())
                if let floor = scene.floor {
                    Text(
                        "floor: \(CharacterName.of(floor.characterID)) until \(floor.deadline, format: .dateTime.hour().minute().second())"
                    )
                    .foregroundStyle(.orange)
                }
                if let reason = scene.closeReason {
                    Text("closed: \(reason.rawValue)")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            ForEach(Array(scene.turns.enumerated()), id: \.offset) { _, turn in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CharacterName.of(turn.characterID))
                        .font(.caption.weight(.semibold))
                    if let text = turn.text {
                        Text(text)
                            .font(.caption)
                    } else {
                        Text("passes")
                            .font(.caption.italic())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if let floor = scene.floor, !floor.pieces.isEmpty {
                // A line still being composed: the sentences the room has heard so far.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CharacterName.of(floor.characterID))
                        .font(.caption.weight(.semibold))
                    Text(floor.pieces.joined(separator: " ") + " …")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let performance = scene.performance {
                Text(
                    performance.state == .failed
                        ? "performance failed: \(performance.errorCode ?? "unknown")"
                        : "performance \(performance.state.rawValue)"
                            + (performance.providerReference.map { " · \($0)" } ?? "")
                )
                .font(.caption2)
                .foregroundStyle(performance.state == .failed ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch scene.state {
        case .open: .yellow
        case .rendering: .orange
        case .performed: .green
        case .abandoned: .gray
        }
    }
}

enum CharacterName {
    /// `character:beaky` → `Beaky`.
    static func of(_ entityID: EntityID) -> String {
        let raw = entityID.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        return String(raw[raw.index(after: colon)...]).capitalized
    }
}
