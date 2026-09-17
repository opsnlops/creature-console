import SwiftUI
import WorldCore

/// What the World currently believes. Empty until the first reducer lands — and honest about it.
/// Its Meanings mode is Wizard Mode's one cast: what each kind of fact means to the minds.
struct FactsPanel: View {
    private enum Mode: String, CaseIterable {
        case facts = "Facts"
        case meanings = "Meanings"
    }

    let store: WorldStore
    @Binding var scried: Scried?
    @State private var selection: FactID?
    @State private var mode: Mode = .facts
    @State private var asking: WhySheet.Asking?

    var body: some View {
        Group {
            switch mode {
            case .facts: factList
            case .meanings: MeaningsList(store: store)
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.refreshFactsAndTimers() }
                }
            }
        }
        .sheet(item: $asking) { WhySheet(store: store, fact: $0.fact) }
    }

    private var factList: some View {
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
            .contextMenu {
                Button("Show \(fact.subjectID.rawValue)", systemImage: "person.text.rectangle") {
                    store.chosenEntity = fact.subjectID
                }
                if let target = WorldFacts.link(in: fact.value) {
                    Button("Show \(target.rawValue)", systemImage: "arrow.turn.down.right") {
                        store.chosenEntity = target
                    }
                }
                Button("Why?", systemImage: "questionmark.circle") { asking = .init(fact) }
                Divider()
                // Any fact can be taken back: the world casts nothing in its place.
                Button("Forget", systemImage: "eraser") {
                    Task { await store.forget(fact.subjectID, fact.predicate) }
                }
                .help("Retract this fact: the World will believe it no longer")
            }
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

/// The world's glossary, editable in place. A word the world believes something under but has
/// no meaning for yet sits at the top, waiting to be taught.
private struct MeaningsList: View {
    let store: WorldStore

    var body: some View {
        List {
            if !store.undefinedPredicates.isEmpty {
                Section("New words: the World believes these but cannot say what they mean") {
                    ForEach(store.undefinedPredicates, id: \.self) { predicate in
                        MeaningRow(
                            predicate: predicate, meaning: "", updatedBy: nil, audience: nil,
                            store: store)
                    }
                }
            }
            Section("What each kind of fact means, and who it is for") {
                ForEach(store.factKinds, id: \.predicate) { kind in
                    MeaningRow(
                        predicate: kind.predicate, meaning: kind.meaning,
                        updatedBy: kind.updatedBy, audience: kind.audience, store: store)
                }
            }
        }
        .overlay {
            if store.factKinds.isEmpty && store.undefinedPredicates.isEmpty {
                ContentUnavailableView(
                    "No meanings yet", systemImage: "character.book.closed",
                    description: Text("The World seeds its glossary when it starts."))
            }
        }
    }
}

private struct MeaningRow: View {
    let predicate: String
    let meaning: String
    let updatedBy: String?
    /// nil for a word the world has no meaning for yet.
    let audience: FactAudience?
    let store: WorldStore
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(predicate).font(.headline.monospaced())
                Spacer()
                if let updatedBy, updatedBy != "world:catalogue" {
                    Text("reworded by \(updatedBy)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let audience {
                    // Who this kind is for: the birds, or the world alone (a phone number).
                    Picker(
                        "Audience",
                        selection: Binding(
                            get: { audience },
                            set: { new in
                                Task {
                                    await store.reword(predicate, meaning: meaning, audience: new)
                                }
                            })
                    ) {
                        Text("minds").tag(FactAudience.minds)
                        Text("world only").tag(FactAudience.world)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .fixedSize()
                    .help(
                        "minds: handed to the birds. world only: kept and shown here, never put in a prompt."
                    )
                }
            }
            TextField("What does this mean to a bird?", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                // Take the row's width and wrap; never claim an ideal width of its own.
                .fixedSize(horizontal: false, vertical: true)
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, focused in
                    if !focused { commit() }
                }
        }
        .padding(.vertical, 3)
        .onAppear { draft = meaning }
        .onChange(of: meaning) { _, new in
            if !editing { draft = new }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != meaning else { return }
        Task { await store.reword(predicate, meaning: trimmed) }
    }
}
