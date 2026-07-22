import Common
import OSLog
import SwiftUI

/// CRUD list of `FixturePattern` entries on a fixture. Each pattern expands inline
/// into a `PatternValueEditor` plus fade-timing controls and a "Fire" trigger button.
struct PatternListEditor: View {

    @Binding var fixture: Common.DmxFixture

    let server: CreatureServerClient
    /// True while the local LiveControlPanel is driving DMX. The server refuses pattern
    /// triggers during a live session, so disabling the fire buttons keeps the UI in
    /// sync rather than surfacing 400s.
    let liveActive: Bool
    /// Callback the surrounding editor uses to surface trigger errors via its alert
    /// machinery. Kept as a closure so this view doesn't need its own alert state.
    let onTriggerError: (_ title: String, _ message: String) -> Void

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "PatternListEditor")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Patterns").font(.headline)
                Spacer()
                Text("\(fixture.patterns.count) / 256 max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: addPattern) {
                    Label("Add Pattern", systemImage: "plus.circle")
                }
                .disabled(fixture.patterns.count >= 256)
            }

            if fixture.patterns.isEmpty {
                Text("Add a pattern to define a named DMX snapshot that bindings can fire.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(fixture.patterns.enumerated()), id: \.element.id) { index, pattern in
                patternRow(at: index, pattern: pattern)
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func patternRow(at index: Int, pattern: FixturePattern) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Name").frame(width: 80, alignment: .leading)
                    TextField(
                        "Pattern name",
                        text: Binding(
                            get: { fixture.patterns[index].name },
                            set: { fixture.patterns[index].name = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                fadeTimingRow(at: index)

                PatternValueEditor(
                    fixture: $fixture,
                    patternIndex: index
                )

                triggerRow(for: pattern)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(pattern.name.isEmpty ? "(unnamed)" : pattern.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(pattern.values.count) values")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    fixture.patterns.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func fadeTimingRow(at index: Int) -> some View {
        HStack {
            timingField(label: "Fade-in (ms)", binding: fadeInBinding(at: index))
            timingField(label: "Hold (ms)", binding: holdBinding(at: index))
            timingField(label: "Fade-out (ms)", binding: fadeOutBinding(at: index))
        }
    }

    private func timingField(label: String, binding: Binding<UInt32>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(
                "ms",
                value: Binding<Int>(
                    get: { Int(binding.wrappedValue) },
                    set: { binding.wrappedValue = UInt32(clamping: max(0, $0)) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 120)
        }
    }

    private func fadeInBinding(at index: Int) -> Binding<UInt32> {
        Binding(
            get: { fixture.patterns[index].fadeInMs },
            set: { fixture.patterns[index].fadeInMs = $0 }
        )
    }

    private func holdBinding(at index: Int) -> Binding<UInt32> {
        Binding(
            get: { fixture.patterns[index].holdMs },
            set: { fixture.patterns[index].holdMs = $0 }
        )
    }

    private func fadeOutBinding(at index: Int) -> Binding<UInt32> {
        Binding(
            get: { fixture.patterns[index].fadeOutMs },
            set: { fixture.patterns[index].fadeOutMs = $0 }
        )
    }

    // MARK: - Trigger

    @ViewBuilder
    private func triggerRow(for pattern: FixturePattern) -> some View {
        if fixture.assignedUniverse == nil {
            Label(
                "Assign a universe to fire patterns from here.",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack {
                Button {
                    triggerPattern(pattern, stopAfterMs: nil)
                } label: {
                    Label("Fire (hold)", systemImage: "play.circle")
                }
                .disabled(liveActive)
                Button {
                    triggerPattern(pattern, stopAfterMs: 1500)
                } label: {
                    Label("Fire 1.5s", systemImage: "timer")
                }
                .disabled(liveActive)
                Button {
                    triggerPattern(pattern, stopAfterMs: 5000)
                } label: {
                    Label("Fire 5s", systemImage: "timer")
                }
                .disabled(liveActive)
                Spacer()
                if liveActive {
                    Text("Live control is driving this fixture — pattern fires refused.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("Fires preview — uses your current edits, no save needed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Fires the pattern using the editor's *current local* values + fade timings via
    /// the preview endpoint, so the user sees what they're authoring (not what the
    /// server has stored). Nothing is persisted server-side — once the user is happy,
    /// they hit Save in the toolbar to upsert the fixture.
    private func triggerPattern(_ pattern: FixturePattern, stopAfterMs: UInt32?) {
        let fixtureId = fixture.id
        let values = pattern.values
        let fadeInMs = pattern.fadeInMs
        let fadeOutMs = pattern.fadeOutMs
        let holdMs = pattern.holdMs
        Task {
            let result = await server.previewFixturePattern(
                fixtureId: fixtureId,
                values: values,
                fadeInMs: fadeInMs,
                fadeOutMs: fadeOutMs,
                holdMs: holdMs,
                stopAfterMs: stopAfterMs
            )
            await MainActor.run {
                switch result {
                case .success(let updated):
                    logger.info("preview ok on fixture \(updated.id)")
                case .failure(let error):
                    onTriggerError(
                        "Preview Failed", ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func addPattern() {
        let name = "Pattern \(fixture.patterns.count + 1)"
        let id = UUID().uuidString.lowercased()
        fixture.patterns.append(
            FixturePattern(
                id: id,
                name: name,
                values: [],
                fadeInMs: 0,
                fadeOutMs: 0,
                holdMs: 0
            )
        )
    }
}
