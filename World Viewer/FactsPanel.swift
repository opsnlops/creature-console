import SwiftUI
import WorldCore

/// What the World currently believes. Empty until the first reducer lands — and honest about it.
struct FactsPanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var selection: FactID?

    var body: some View {
        List(store.facts, id: \.factID, selection: $selection) { fact in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(fact.subjectID.rawValue) · \(fact.predicate)")
                        .font(.headline)
                    Text(describe(fact.value))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        EpistemicChip(state: fact.epistemic)
                        Text("since \(fact.validFrom, format: .dateTime.hour().minute().second())")
                        Text(
                            "by \(fact.producer.kind) \(fact.producer.id) \(fact.producer.version)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
        .onChange(of: selection) { _, factID in
            scried = store.facts.first { $0.factID == factID }.map(Scried.fact)
        }
        .overlay {
            if store.facts.isEmpty {
                ContentUnavailableView(
                    "The World believes nothing yet",
                    systemImage: "sparkles.rectangle.stack",
                    description: Text(
                        "Facts appear when a reducer derives them from events. There are no reducers yet."
                    )
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.factsTruncated {
                Text("Showing the first page of facts; the World holds more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.refreshFactsAndTimers() }
                }
            }
        }
    }

    private func describe(_ value: WorldJSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let bool): String(bool)
        case .number(let number): number.formatted()
        case .string(let string): string
        case .array, .object:
            String(
                decoding: (try? WorldJSON.makeEncoder().encode(value)) ?? Data(), as: UTF8.self)
        }
    }
}
