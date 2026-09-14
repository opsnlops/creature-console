import SwiftUI
import WorldCore

/// Every event the World has sequenced, newest last, with the lag between when it happened and
/// when the World took it in.
struct TimelinePanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var filter = ""
    @State private var selection: EventID?

    var body: some View {
        List(filteredEvents.reversed(), id: \.eventID, selection: $selection) { event in
            TimelineRow(event: event)
        }
        .searchable(text: $filter, prompt: "Filter by type, subject, or source")
        .onChange(of: selection) { _, eventID in
            scried = store.events.first { $0.eventID == eventID }.map(Scried.event)
        }
        .overlay {
            if store.events.isEmpty {
                ContentUnavailableView(
                    "Nothing has happened yet",
                    systemImage: "clock",
                    description: Text(
                        "Events appear here the moment the World sequences them. Say something to Beaky."
                    )
                )
            } else if filteredEvents.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
    }

    private var filteredEvents: [WorldEventEnvelope] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return store.events }
        return store.events.filter { event in
            event.type.rawValue.contains(needle)
                || event.source.id.rawValue.lowercased().contains(needle)
                || event.source.kind.lowercased().contains(needle)
                || event.subjectIDs.contains { $0.rawValue.lowercased().contains(needle) }
        }
    }
}

struct TimelineRow: View {
    let event: WorldEventEnvelope

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.worldSequence.map(String.init) ?? "—")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(minWidth: 56, alignment: .trailing)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(event.type.rawValue)
                        .font(.headline)
                        .foregroundStyle(isProblem ? .red : .primary)
                    EpistemicChip(state: event.epistemic)
                }
                Text(subjects)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let problem {
                    // The room could not be readied, or a performance failed: say why, here,
                    // not in a log on the server.
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if event.type == SceneService.remarkDeclinedEventType,
                    case .string(let reason)? = event.payload["reason"]
                {
                    // Considered, stayed quiet: her judgement, on the record.
                    Label("stayed quiet: \(reason)", systemImage: "moon.zzz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Text("\(event.source.kind) · \(event.source.id.rawValue)")
                    Text(event.occurredAt, format: .dateTime.hour().minute().second())
                    if let lag {
                        Text("lag \(lag, format: .number.precision(.fractionLength(0))) ms")
                            .foregroundStyle(lag > 2_000 ? .orange : .secondary)
                    }
                    TraceLink(trace: event.trace)
                    if let knownFacts {
                        Label("knows \(knownFacts)", systemImage: "lightbulb")
                            .help("Facts the world told the mind with this percept")
                    }
                    if let happenings, happenings > 0 {
                        Label("saw \(happenings)", systemImage: "book.pages")
                            .help(
                                "Recent happenings the world told the mind — the story behind the facts"
                            )
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    /// A stage problem or a failed performance carries its reason in the payload.
    private var isProblem: Bool {
        event.type == SceneService.stageProblemEventType
            || event.type.rawValue.hasSuffix("performance_failed")
            || (event.type == SceneService.performedEventType && failedPerformance)
    }

    private var failedPerformance: Bool {
        guard case .object(let performance)? = event.payload["performance"] else { return false }
        return performance["state"] == .string("failed")
    }

    private var problem: String? {
        if case .string(let message)? = event.payload["message"],
            event.type == SceneService.stageProblemEventType
        {
            return message
        }
        if case .object(let performance)? = event.payload["performance"],
            performance["state"] == .string("failed")
        {
            if case .string(let message)? = performance["error_message"] { return message }
            if case .string(let code)? = performance["error_code"] { return code }
        }
        return nil
    }

    private var subjects: String {
        event.subjectIDs.isEmpty
            ? "no subjects" : event.subjectIDs.map(\.rawValue).joined(separator: ", ")
    }

    private var lag: Double? {
        event.receivedAt.map { $0.timeIntervalSince(event.occurredAt) * 1_000 }
    }

    /// A percept (an utterance for a mind, a floor offer) carries what the world knew at that
    /// moment; the exact facts are in the Mundane view.
    private var knownFacts: Int? {
        guard case .array(let facts)? = event.payload["world_facts"] else { return nil }
        return facts.count
    }

    private var happenings: Int? {
        guard case .array(let story)? = event.payload["recent_happenings"] else { return nil }
        return story.count
    }
}

struct EpistemicChip: View {
    let state: EpistemicState

    var body: some View {
        Text(
            "\(state.type.rawValue) \(state.confidence, format: .percent.precision(.fractionLength(0)))"
        )
        .font(.caption2)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .glassEffect(.regular.tint(.blue.opacity(0.15)), in: .capsule)
    }
}
