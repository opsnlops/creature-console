import Common
import SwiftData
import SwiftUI

/// CRUD list of `FixtureBinding` rows: each ties a creature's `(reason, state)` activity
/// transitions to a pattern on this fixture. Creature picker is sourced from
/// `CreatureModel` via `@Query`; a "manual UUID" fallback lets the user save a binding
/// against a creature ID that isn't in the local cache (the dispatcher won't fire until
/// the creature exists on the server, but that's a soft warning, not a hard block).
struct BindingListEditor: View {

    @Binding var fixture: Common.DmxFixture

    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bindings").font(.headline)
                Spacer()
                Text("\(fixture.bindings.count) / 256 max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: addBinding) {
                    Label("Add Binding", systemImage: "plus.circle")
                }
                .disabled(fixture.bindings.count >= 256 || fixture.patterns.isEmpty)
            }

            if fixture.patterns.isEmpty {
                Text("Add at least one pattern before adding bindings (a binding fires a pattern).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(Array(fixture.bindings.enumerated()), id: \.element.id) { index, _ in
                bindingRow(at: index)
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func bindingRow(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Creature").frame(width: 80, alignment: .leading)
                Picker(
                    "",
                    selection: Binding(
                        get: { fixture.bindings[index].creatureId },
                        set: { fixture.bindings[index].creatureId = $0 }
                    )
                ) {
                    if !creatures.contains(where: { $0.id == fixture.bindings[index].creatureId })
                        && !fixture.bindings[index].creatureId.isEmpty
                    {
                        // Preserve a creature ID that isn't in our local cache (e.g.
                        // recently created on another client). Show it as an "unknown"
                        // option so the user can keep it.
                        Text(
                            "Unknown / external: \(shortId(fixture.bindings[index].creatureId))"
                        )
                        .tag(fixture.bindings[index].creatureId)
                    }
                    ForEach(creatures, id: \.id) { creature in
                        Text(creature.name).tag(creature.id)
                    }
                }
                .labelsHidden()

                Spacer()

                Button(role: .destructive) {
                    fixture.bindings.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Text("On reason").frame(width: 80, alignment: .leading)
                Picker(
                    "",
                    selection: Binding(
                        get: { fixture.bindings[index].onReason },
                        set: { fixture.bindings[index].onReason = $0 }
                    )
                ) {
                    Text("Any").tag(Optional<ActivityReason>.none)
                    ForEach(reasonPickerCases, id: \.self) { reason in
                        Text(displayName(for: reason)).tag(Optional(reason))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("On state").frame(width: 80, alignment: .leading)
                Picker(
                    "",
                    selection: Binding(
                        get: { fixture.bindings[index].onState },
                        set: { fixture.bindings[index].onState = $0 }
                    )
                ) {
                    Text("Any").tag(Optional<ActivityState>.none)
                    ForEach(statePickerCases, id: \.self) { state in
                        Text(displayName(for: state)).tag(Optional(state))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Pattern").frame(width: 80, alignment: .leading)
                Picker(
                    "",
                    selection: Binding(
                        get: { fixture.bindings[index].patternId },
                        set: { fixture.bindings[index].patternId = $0 }
                    )
                ) {
                    ForEach(fixture.patterns, id: \.id) { pattern in
                        Text(pattern.name).tag(pattern.id)
                    }
                }
                .labelsHidden()
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func addBinding() {
        guard let firstPattern = fixture.patterns.first else { return }
        let creatureId = creatures.first?.id ?? ""
        fixture.bindings.append(
            FixtureBinding(
                creatureId: creatureId,
                onReason: nil,
                onState: nil,
                patternId: firstPattern.id
            )
        )
    }

    private func shortId(_ id: String) -> String {
        if id.count > 8 { return String(id.prefix(8)) + "…" }
        return id
    }

    /// All reasons except `.unknown` (which exists for liberal decoding but shouldn't be
    /// authored from the UI).
    private var reasonPickerCases: [ActivityReason] {
        [.play, .playlist, .adHoc, .idle, .disabled, .cancelled, .streaming]
    }

    private var statePickerCases: [ActivityState] {
        [.running, .idle, .disabled, .stopped]
    }

    private func displayName(for reason: ActivityReason) -> String {
        switch reason {
        case .play: return "play"
        case .playlist: return "playlist"
        case .adHoc: return "ad_hoc"
        case .idle: return "idle"
        case .disabled: return "disabled"
        case .cancelled: return "cancelled"
        case .streaming: return "streaming"
        case .unknown: return "unknown"
        }
    }

    private func displayName(for state: ActivityState) -> String {
        switch state {
        case .running: return "running"
        case .idle: return "idle"
        case .disabled: return "disabled"
        case .stopped: return "stopped"
        case .unknown: return "unknown"
        }
    }
}
