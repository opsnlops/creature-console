import SwiftUI
import WorldCore

/// Why?: the provenance walk behind one fact - what the world was told, by whom, when, and
/// what came of it. VW-011. The same walk WorldMCP's `explain_fact` makes; this is the eye.
struct WhySheet: View {
    @Bindable var store: WorldStore
    let fact: Fact
    @Environment(\.dismiss) private var dismiss
    @State private var explanation: WorldStore.Explanation?

    /// The fact a panel is asking about; `sheet(item:)` wants an identity and `Fact` is not
    /// Identifiable in WorldCore.
    struct Asking: Identifiable {
        let fact: Fact
        var id: FactID { fact.factID }
        init(_ fact: Fact) { self.fact = fact }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Why?", systemImage: "questionmark.circle")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            factCard(fact, title: "The fact")
            switch explanation {
            case nil:
                ProgressView("Asking the world…")
                    .frame(maxWidth: .infinity)
            case .gone:
                Text("The world has let this fact go; there is nothing left to explain.")
                    .foregroundStyle(.secondary)
            case .failed:
                Text("The world could not be asked.")
                    .foregroundStyle(.secondary)
            case .explained(let explanation):
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if explanation.events.isEmpty && explanation.facts.isEmpty {
                            Text("The world holds no record of where this came from.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(explanation.events, id: \.eventID) { event in
                            eventCard(event)
                        }
                        ForEach(explanation.facts, id: \.factID) { earlier in
                            factCard(earlier, title: "Derived from")
                        }
                        if let successor = explanation.supersededBy {
                            factCard(successor, title: "Superseded by")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
        .task { explanation = await store.explain(fact.factID) }
    }

    private func factCard(_ fact: Fact, title: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(fact.subjectID.rawValue).fontWeight(.medium)
                    Text("·").foregroundStyle(.tertiary)
                    Text(fact.predicate).font(.system(.body, design: .monospaced))
                }
                Text(describe(fact.value))
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(basis(fact.epistemic))
                    Text("since \(fact.validFrom, format: .dateTime.month().day().hour().minute())")
                    if let until = fact.validTo {
                        Text("until \(until, format: .dateTime.month().day().hour().minute())")
                    }
                    Text("by \(fact.producer.kind) \(fact.producer.id)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func eventCard(_ event: WorldEventEnvelope) -> some View {
        GroupBox("Because the world was told") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.type.rawValue).font(.system(.body, design: .monospaced))
                    Text("from \(event.source.id.rawValue)")
                        .foregroundStyle(.secondary)
                }
                Text(
                    "\(event.occurredAt, format: .dateTime.month().day().hour().minute().second()) · \(basis(event.epistemic))"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                ForEach(event.payload.keys.sorted(), id: \.self) { key in
                    if let value = event.payload[key] {
                        HStack(alignment: .top, spacing: 6) {
                            Text(key).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(describe(value)).font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func basis(_ epistemic: EpistemicState) -> String {
        epistemic.confidence < 0.999
            ? "\(epistemic.type.rawValue) (\(Int((epistemic.confidence * 100).rounded()))%)"
            : epistemic.type.rawValue
    }

    private func describe(_ value: WorldJSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let bool): String(bool)
        case .number(let number): number.formatted()
        case .string(let text): text
        case .array, .object:
            (try? String(decoding: WorldJSON.makeEncoder().encode(value), as: UTF8.self)) ?? "…"
        }
    }
}
