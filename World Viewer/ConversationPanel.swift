import SwiftUI
import WorldCore

/// The conversation as the World remembers it, newest turn at the top, with how each bird's
/// turn reached April: the router's decision (the route, why, and how the delivery went), or,
/// for a turn in a scene, how the scene's performance went.
struct ConversationPanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var selection: ConversationItemID?

    var body: some View {
        List(store.conversationItems.reversed(), id: \.itemID, selection: $selection) { item in
            ConversationTurnRow(item: item, record: record(for: item))
        }
        .onChange(of: selection) { _, itemID in
            scried = store.conversationItems.first { $0.itemID == itemID }
                .map { Scried.turn($0, record(for: $0)) }
        }
        .overlay {
            if store.conversationItems.isEmpty {
                ContentUnavailableView(
                    "No turns yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(
                        "\(store.conversationID.rawValue) is empty, or the World has not answered."
                    )
                )
            }
        }
    }

    private func record(for item: ConversationItem) -> TurnRecord {
        TurnRecord(
            delivery: item.responseID.flatMap { store.deliveries[$0] },
            scene: item.responseID.flatMap { store.scenesByResponse[$0] }
        )
    }
}

/// How a bird's turn reached April (#295): a turn answered alone goes through the router and
/// has a delivery; a turn in a scene is performed with the scene's other lines, and the scene
/// holds how that went. Either, or neither when the record is not among those loaded.
struct TurnRecord: Hashable {
    var delivery: CharacterDeliveryRecord?
    var scene: WorldCore.Scene?
}

struct ConversationTurnRow: View {
    let item: ConversationItem
    let record: TurnRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.authorKind == .character ? "bird.fill" : "person.fill")
                .font(.title3)
                .foregroundStyle(item.authorKind == .character ? .orange : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.authorID.rawValue)
                        .font(.headline)
                    Text(item.createdAt, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    TraceLink(trace: item.trace)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let bird = item.aloneWith {
                        WhisperedLabel(bird: bird)
                    }
                }
                PerformedLine(item.performed ?? item.text)
                    .textSelection(.enabled)
                if let delivery = record.delivery {
                    DeliveryChip(delivery: delivery)
                    if let outcome = delivery.outcome, outcome.state == .failed {
                        // Why, in the refusing service's own words — the difference between
                        // "physical_speech_start_failed" and "Is the controller online?".
                        Label(
                            outcome.errorMessage ?? "No reason was recorded (before World 0.19).",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    }
                } else if let scene = record.scene {
                    ScenePerformanceChip(scene: scene)
                    if let performance = scene.performance, performance.state == .failed {
                        Label(
                            performance.errorMessage ?? performance.errorCode
                                ?? "No reason was recorded.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    }
                } else if item.authorKind == .character {
                    // Say only what is known: the Viewer holds the newest deliveries and
                    // scenes, not all of them, so an older turn may simply be out of reach.
                    Text("No delivery or scene record among those loaded.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A bird's line as its voice performed it (#270): a cue in italics among the words, where the
/// room heard the sigh. The Communicator and the minds see only the words.
struct PerformedLine: View {
    let line: String

    init(_ line: String) {
        self.line = line
    }

    var body: some View {
        Text(styled)
    }

    private var styled: AttributedString {
        var styled = AttributedString()
        var rest = Substring(line)
        for cue in VoiceCues.cues(in: line) {
            guard let range = rest.range(of: cue) else { continue }
            styled += AttributedString(rest[..<range.lowerBound])
            var performed = AttributedString(cue)
            performed.inlinePresentationIntent = .emphasized
            performed.foregroundColor = .secondary
            styled += performed
            rest = rest[range.upperBound...]
        }
        return styled + AttributedString(rest)
    }
}

/// Between April and one bird: a whispered turn (#261), or a fact learned in a whisper (#263).
struct WhisperedLabel: View {
    let bird: EntityID

    var body: some View {
        Label(
            "whispered with \(WorldFacts.memoryOwner(for: bird).capitalized)",
            systemImage: "lock.fill"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help("Between April and this bird alone; the other birds are never handed it")
    }
}

/// How the scene that spoke a bird's turn went (#295): the room heard it once the scene
/// performed; before that it is being composed or rendered.
struct ScenePerformanceChip: View {
    let scene: WorldCore.Scene

    var body: some View {
        HStack(spacing: 10) {
            Label("scene", systemImage: "person.3.fill")
            if let reason = scene.closeReason {
                Text(reason.rawValue)
            }
            Text(state)
                .foregroundStyle(failed ? .red : .primary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
        .help(hint)
    }

    private var failed: Bool {
        scene.performance?.state == .failed || scene.state == .abandoned
    }

    private var state: String {
        if let performance = scene.performance {
            return performance.state == .failed
                ? "failed: \(performance.errorCode ?? "unknown")" : performance.state.rawValue
        }
        return switch scene.state {
        case .open: "composing"
        case .rendering: "rendering"
        case .performed: "performed"
        case .abandoned: "abandoned"
        }
    }

    private var tint: Color {
        if failed { return .red }
        return scene.performance?.state == .performed || scene.state == .performed
            ? .green : .gray
    }

    private var hint: String {
        var parts = [
            scene.sceneID.rawValue,
            "opened \(scene.openedAt.formatted(.dateTime.hour().minute().second()))",
            "\(scene.turns.filter { $0.text != nil }.count) spoken of \(scene.turns.count) turns",
        ]
        if let reference = scene.performance?.providerReference {
            parts.append("performance \(reference)")
        }
        return parts.joined(separator: " · ")
    }
}

/// What the router decided for one of Beaky's turns.
struct DeliveryChip: View {
    let delivery: CharacterDeliveryRecord

    var body: some View {
        HStack(spacing: 10) {
            Label(delivery.decision.route.rawValue, systemImage: routeSymbol)
            Text(delivery.decision.reason.rawValue)
            Text(presence)
            if let outcome = delivery.outcome {
                Text(
                    outcome.state == .failed
                        ? "failed: \(outcome.errorCode ?? "unknown")" : outcome.state.rawValue
                )
                .foregroundStyle(outcome.state == .failed ? .red : .primary)
            } else {
                Text("no outcome")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
        .help(hint)
    }

    private var hint: String {
        var parts = [
            "attempt \(delivery.decision.attemptID.rawValue)",
            "decided \(delivery.decision.decidedAt.formatted(.dateTime.hour().minute().second()))",
        ]
        if let reference = delivery.outcome?.providerReference {
            parts.append("performance \(reference)")
        }
        if let code = delivery.outcome?.errorCode {
            parts.append("error \(code)")
        }
        return parts.joined(separator: " · ")
    }

    private var presence: String {
        let seen = delivery.decision.presence
        let audible = seen.physicallyAudible ? "audible" : "not audible"
        return
            "\(seen.state.rawValue) \(seen.confidence.formatted(.percent.precision(.fractionLength(0)))) (\(seen.basis.rawValue)) · \(audible)"
    }

    private var routeSymbol: String {
        switch delivery.decision.route {
        case .physicalSpeech: "speaker.wave.2.fill"
        case .communicator: "iphone"
        }
    }

    private var tint: Color {
        switch delivery.decision.route {
        case .physicalSpeech: .green
        case .communicator: .purple
        }
    }
}
