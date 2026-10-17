import SwiftUI
import WorldCore

/// What a bird is handed, as the words of the moment would bring it: the page, counted by what
/// it holds. April: "I want to have high quality conversations with the birds. We need the
/// facts to be as full of context as we can." On 2026-10-16 Beaky's thirty held one thing April
/// had told her (#231); this is where that number is read.
struct PagePanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var character: EntityID?
    @State private var words = ""
    @State private var page: CharacterPerspective?
    @State private var loading = false

    private var birds: [EntityID] {
        Array(Set(store.characters.map(\.characterID))).sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Picker("Bird", selection: $character) {
                    Text("Pick a bird").tag(EntityID?.none)
                    ForEach(birds, id: \.self) { bird in
                        Text(FactPageSections.name(of: bird)).tag(EntityID?.some(bird))
                    }
                }
                .frame(maxWidth: 200)
                TextField("What April says (optional)", text: $words)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await load() } }
                Button("Read the Page", systemImage: "doc.text.magnifyingglass") {
                    Task { await load() }
                }
                .buttonStyle(.glassProminent)
                .disabled(character == nil || loading)
            }
            .padding(12)
            Divider()
            Group {
                if loading {
                    ProgressView()
                } else if let page {
                    PageView(
                        sections: FactPageSections(
                            facts: page.facts, calledUp: Set(page.calledUp ?? [])),
                        scried: $scried)
                } else {
                    ContentUnavailableView(
                        "Read a bird's page", systemImage: "doc.text",
                        description: Text(
                            "Exactly what its mind is handed: the thirty, and what rides beside them."
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { if character == nil { character = birds.first } }
    }

    private func load() async {
        guard let character else { return }
        loading = true
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        page = await store.perspective(of: character, mentionedIn: trimmed.isEmpty ? nil : trimmed)
        loading = false
    }
}

/// A page sorted by what each fact is: what the words called up, then the standing page - what
/// the birds learned, the house's state, the calendar, memories, and what rides beside the
/// thirty, the folded state and the stage. The standing page is what a mind keeps cached all
/// day; what the words called up is sent fresh with each scene (#245).
struct FactPageSections: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case calledUp = "Called up by the words"
        case learned = "What the birds learned"
        case state = "The house and the world, now"
        case folded = "Folded: sensors and forecasts"
        case calendar = "Calendar and reminders"
        case memories = "Memories"
        case stage = "The stage: who is here, and how to name them"

        var id: String { rawValue }
    }

    let facts: [Fact]
    /// The facts the words called up, from the world's `called_up`.
    var calledUp: Set<FactID> = []

    static let stagePredicates: Set<String> = [WorldFacts.characterRegion, WorldFacts.pronouns]

    static func kind(of fact: Fact) -> Kind {
        if stagePredicates.contains(fact.predicate) { return .stage }
        if fact.predicate.hasPrefix("memory.") { return .memories }
        // The calendar is the calendar, folded into a line an event or not (#232).
        let subject = fact.subjectID.rawValue
        if subject.hasPrefix("event:") || subject.hasPrefix("reminder:") { return .calendar }
        if fact.producer.kind == "world" && fact.producer.id == "page" { return .folded }
        if let origin = fact.origin?.rawValue,
            origin.hasPrefix("mind:") || origin.hasPrefix("librarian:")
        {
            return .learned
        }
        return .state
    }

    /// Where a fact sits on this page: with what the words called up, or by what it is.
    func section(of fact: Fact) -> Kind {
        calledUp.contains(fact.factID) ? .calledUp : Self.kind(of: fact)
    }

    func facts(of kind: Kind) -> [Fact] {
        facts.filter { section(of: $0) == kind }
    }

    /// "18 learned · 7 state · 2 folded · 6 calendar · 9 memories · 8 stage"
    var summary: String {
        Kind.allCases.compactMap { kind in
            let count = facts(of: kind).count
            guard count > 0 else { return nil }
            let short: String =
                switch kind {
                case .calledUp: "called up"
                case .learned: "learned"
                case .state: "state"
                case .folded: "folded"
                case .calendar: "calendar"
                case .memories: "memories"
                case .stage: "stage"
                }
            return "\(count) \(short)"
        }.joined(separator: " · ")
    }

    static func name(of entity: EntityID) -> String {
        let raw = entity.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        return raw[raw.index(after: colon)...].split(separator: "-").map(\.capitalized)
            .joined(separator: " ")
    }
}

private struct PageView: View {
    let sections: FactPageSections
    @Binding var scried: Scried?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(sections.summary)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.teal.opacity(0.15)), in: .capsule)
                ForEach(FactPageSections.Kind.allCases) { kind in
                    let facts = sections.facts(of: kind)
                    if !facts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(kind.rawValue) (\(facts.count))")
                                .font(.title3.bold())
                            ForEach(facts, id: \.factID) { fact in
                                PageFactRow(fact: fact)
                                    .contentShape(Rectangle())
                                    .onTapGesture { scried = .fact(fact) }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PageFactRow: View {
    let fact: Fact

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(fact.subjectID.rawValue) · \(fact.predicate)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(fact.value.displayText)
                .textSelection(.enabled)
                .lineLimit(4)
            if let kept = fact.keptBy {
                Text(kept)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

}

extension WorldJSONValue {
    /// A value as a line of text: a string as itself, a number without a needless ".0", an
    /// object by its `what` or `text`, an array joined.
    var displayText: String {
        switch self {
        case .string(let text): text
        case .number(let number):
            number == number.rounded() ? String(Int(number)) : String(format: "%.1f", number)
        case .bool(let flag): flag ? "yes" : "no"
        case .null: "none"
        case .object(let fields):
            if case .string(let what)? = fields["what"] {
                what
            } else if case .string(let text)? = fields["text"] {
                text
            } else {
                fields.keys.sorted().joined(separator: ", ")
            }
        case .array(let values): values.map(\.displayText).joined(separator: ", ")
        }
    }
}
