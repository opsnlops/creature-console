import SwiftUI
import WorldCore

/// The conversation as the World remembers it, newest turn at the top, with the router's
/// decision beside each of Beaky's turns: the route it chose, why, and how the delivery went.
struct ConversationPanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var selection: ConversationItemID?

    var body: some View {
        List(store.conversationItems.reversed(), id: \.itemID, selection: $selection) { item in
            ConversationTurnRow(item: item, delivery: delivery(for: item))
        }
        .onChange(of: selection) { _, itemID in
            scried = store.conversationItems.first { $0.itemID == itemID }
                .map { Scried.turn($0, delivery(for: $0)) }
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

    private func delivery(for item: ConversationItem) -> CharacterDeliveryRecord? {
        item.responseID.flatMap { store.deliveries[$0] }
    }
}

struct ConversationTurnRow: View {
    let item: ConversationItem
    let delivery: CharacterDeliveryRecord?

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
                    if item.trace != nil {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .help("Carries a W3C trace context")
                    }
                }
                Text(item.text)
                    .textSelection(.enabled)
                if let delivery {
                    DeliveryChip(delivery: delivery)
                } else if item.authorKind == .character {
                    Text("No delivery record — this turn was cast by hand or pre-dates the router.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
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
                Text(outcome.state.rawValue)
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
        .help(
            "attempt \(delivery.decision.attemptID.rawValue) · decided \(delivery.decision.decidedAt.formatted(.dateTime.hour().minute().second()))"
        )
    }

    private var presence: String {
        let seen = delivery.decision.presence
        let audible = seen.physicallyAudible ? "audible" : "not audible"
        return
            "\(seen.state.rawValue) \(seen.confidence.formatted(.percent.precision(.fractionLength(0)))) · \(audible)"
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
