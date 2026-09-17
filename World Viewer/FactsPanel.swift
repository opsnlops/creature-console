import SwiftUI
import WorldCore

/// What the World currently believes. Empty until the first reducer lands — and honest about it.
/// Its Meanings mode is Wizard Mode's one cast: what each kind of fact means to the minds.
struct FactsPanel: View {
    private enum Mode: String, CaseIterable {
        case facts = "Facts"
        case tree = "Tree"
        case meanings = "Meanings"
    }

    let store: WorldStore
    @Binding var scried: Scried?
    @State private var selection: FactID?
    @State private var chosenNode: String?
    @State private var query = ""
    @State private var mode: Mode = .facts
    @State private var asking: WhySheet.Asking?

    var body: some View {
        Group {
            switch mode {
            case .facts: factList
            case .tree: factTree
            case .meanings: MeaningsList(store: store, scried: $scried)
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
            factRow(fact, heading: "\(fact.subjectID.rawValue) · \(fact.predicate)")
                .contextMenu { factMenu(fact) }
        }
        .onChange(of: selection) { _, factID in
            scried = store.facts.first { $0.factID == factID }.map(Scried.fact)
        }
        .overlay { if store.facts.isEmpty { nothingYet } }
        .safeAreaInset(edge: .bottom) { truncatedNote }
    }

    /// The same facts as an outline: kind › entity › family › fact, with counts on the
    /// branches, narrowed by the search words. April: "I want to be able to browse the facts
    /// in a tree."
    private var factTree: some View {
        let nodes = FactTree.build(FactTree.matching(store.facts, query: query))
        return VStack(spacing: 0) {
            TextField("Narrow to facts mentioning…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(nodes, children: \.children, selection: $chosenNode) { node in
                if let fact = node.fact {
                    factRow(fact, heading: node.title)
                        .contextMenu { factMenu(fact) }
                } else {
                    HStack {
                        Label(node.title, systemImage: node.symbol)
                            .font(node.depth == 0 ? .headline : .body)
                        Spacer()
                        Text("\(node.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .contextMenu {
                        if let entity = node.entity {
                            Button("Show \(entity.rawValue)", systemImage: "person.text.rectangle")
                            {
                                store.chosenEntity = entity
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: chosenNode) { _, id in
            if let id, let fact = FactTree.fact(inNodes: nodes, id: id) {
                scried = .fact(fact)
            }
        }
        .overlay { if store.facts.isEmpty { nothingYet } }
        .safeAreaInset(edge: .bottom) { truncatedNote }
    }

    private func factRow(_ fact: Fact, heading: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(heading)
                .font(.headline)
            Text(describe(fact.value))
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
            HStack(spacing: 8) {
                EpistemicChip(state: fact.epistemic)
                Text("since \(fact.validFrom, format: .dateTime.hour().minute().second())")
                Text("by \(fact.producer.kind) \(fact.producer.id) \(fact.producer.version)")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func factMenu(_ fact: Fact) -> some View {
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

    private var nothingYet: some View {
        ContentUnavailableView(
            "The World believes nothing yet",
            systemImage: "sparkles.rectangle.stack",
            description: Text(
                "Facts appear when a reducer derives them from events. There are no reducers yet."
            )
        )
    }

    @ViewBuilder
    private var truncatedNote: some View {
        if store.factsTruncated {
            Text("Showing the first page of facts; the World holds more.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
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
    @Binding var scried: Scried?

    var body: some View {
        List {
            if !store.undefinedPredicates.isEmpty {
                Section("New words: the World believes these but cannot say what they mean") {
                    ForEach(store.undefinedPredicates, id: \.self) { predicate in
                        MeaningRow(
                            predicate: predicate, meaning: "", updatedBy: nil, audience: nil,
                            evidence: evidence(for: predicate), store: store, scried: $scried)
                    }
                }
            }
            Section("What each kind of fact means, and who it is for") {
                ForEach(store.factKinds, id: \.predicate) { kind in
                    MeaningRow(
                        predicate: kind.predicate, meaning: kind.meaning,
                        updatedBy: kind.updatedBy, audience: kind.audience,
                        evidence: evidence(for: kind.predicate), store: store, scried: $scried)
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

    /// The facts the world holds under this word right now - a memory family's meaning
    /// answers for every day's predicate.
    private func evidence(for predicate: String) -> [Fact] {
        store.facts.filter {
            $0.predicate == predicate || WorldFacts.memoryFamily(of: $0.predicate) == predicate
        }
    }
}

private struct MeaningRow: View {
    let predicate: String
    let meaning: String
    let updatedBy: String?
    /// nil for a word the world has no meaning for yet.
    let audience: FactAudience?
    /// What the world holds under this word now, so the meaning is written to the evidence.
    let evidence: [Fact]
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var draft = ""
    @State private var showingEvidence = false
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
            if !evidence.isEmpty {
                Button {
                    withAnimation { showingEvidence.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showingEvidence ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                        Text(summary)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("What the World holds under this word right now; click a fact to scry it")
                if showingEvidence {
                    ForEach(evidence.prefix(8), id: \.factID) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(fact.subjectID.rawValue)
                                .foregroundStyle(.secondary)
                            Text(FactTree.text(of: fact.value))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                            Spacer()
                            Text(fact.epistemic.type.rawValue)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.caption)
                        .contentShape(Rectangle())
                        .onTapGesture { scried = .fact(fact) }
                    }
                    if evidence.count > 8 {
                        Text("and \(evidence.count - 8) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("no current fact carries this word")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .onAppear { draft = meaning }
        .onChange(of: meaning) { _, new in
            if !editing { draft = new }
        }
    }

    /// "12 current facts on 4 subjects · observed · by reducer house".
    private var summary: String {
        let subjects = Set(evidence.map(\.subjectID)).count
        let bases = Set(evidence.map(\.epistemic.type.rawValue)).sorted().joined(separator: ", ")
        let producers = Set(evidence.map { "\($0.producer.kind) \($0.producer.id)" }).sorted()
            .joined(separator: ", ")
        return
            "\(evidence.count) current fact\(evidence.count == 1 ? "" : "s") on \(subjects) subject\(subjects == 1 ? "" : "s") · \(bases) · by \(producers)"
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != meaning else { return }
        Task { await store.reword(predicate, meaning: trimmed) }
    }
}
