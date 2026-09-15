import SwiftUI
import WorldCore

/// Entities are hubs: everything the world believes about one person, place, bird, thing, or
/// event, from every source, with what points at it and what has happened around it lately.
/// Pick one from the list, type an id, or arrive here from any fact's "Show …".
struct EntitiesPanel: View {
    @Bindable var store: WorldStore
    @Binding var scried: Scried?
    @State private var typed = ""
    @State private var page: EntityPage?
    @State private var loading = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("person:jesse", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .onSubmit {
                        if let id = EntityID(rawValue: typed.trimmingCharacters(in: .whitespaces)) {
                            store.chosenEntity = id
                        }
                    }
                    .padding(10)
                List(store.knownEntities, id: \.self, selection: $store.chosenEntity) { entity in
                    Label(entity.rawValue, systemImage: symbol(for: entity))
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            Group {
                if let page {
                    EntityPageView(page: page, store: store, scried: $scried)
                } else if loading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "Pick an entity", systemImage: "person.text.rectangle",
                        description: Text(
                            "Everything the World believes about one person, place, bird, thing, or event — from every source."
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: store.chosenEntity) {
            guard let chosen = store.chosenEntity else { return }
            loading = true
            page = await store.entity(chosen)
            loading = false
            if let page {
                scried = .entity(page)
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    let chosen = store.chosenEntity
                    store.chosenEntity = nil
                    store.chosenEntity = chosen
                }
            }
        }
    }

    private func symbol(for entity: EntityID) -> String {
        switch entity.rawValue.prefix { $0 != ":" } {
        case "person": "person"
        case "character": "bird"
        case "place": "mappin.and.ellipse"
        case "house": "house"
        case "thing": "shippingbox"
        case "event": "calendar"
        case "order": "cart"
        case "region": "map"
        default: "questionmark.square.dashed"
        }
    }
}

/// One entity, whole. Facts the birds are handed in the normal colour, world-only facts in grey;
/// links out and in as buttons that open the other entity; memories apart; recent events last.
struct EntityPageView: View {
    let page: EntityPage
    let store: WorldStore
    @Binding var scried: Scried?

    private var memories: [Fact] {
        page.facts.filter { WorldFacts.memoryFamily(of: $0.predicate) != nil }
    }
    private var present: [Fact] {
        page.facts.filter { WorldFacts.memoryFamily(of: $0.predicate) == nil }
    }

    var body: some View {
        List {
            Section {
                ForEach(present, id: \.factID) { fact in
                    factRow(fact)
                }
                if present.isEmpty {
                    Text("The World believes nothing about this yet.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(page.entityID.rawValue)
                    .font(.title3.monospaced())
            }
            if !page.linkedFrom.isEmpty {
                Section("Pointed at by") {
                    ForEach(page.linkedFrom, id: \.factID) { fact in
                        HStack {
                            Button(fact.subjectID.rawValue) { store.chosenEntity = fact.subjectID }
                                .buttonStyle(.link)
                                .font(.system(.body, design: .monospaced))
                            Text("· \(fact.predicate)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !memories.isEmpty {
                Section("Remembered") {
                    ForEach(memories, id: \.factID) { fact in
                        factRow(fact)
                    }
                }
            }
            if !page.events.isEmpty {
                Section("Lately") {
                    ForEach(page.events, id: \.eventID) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(event.occurredAt, format: .dateTime.weekday().hour().minute())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text(event.type.rawValue)
                            Text(event.source.id.rawValue)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .contentShape(Rectangle())
                        .onTapGesture { scried = .event(event) }
                    }
                }
            }
        }
    }

    private func factRow(_ fact: Fact) -> some View {
        let worldOnly = store.audience(of: fact.predicate) == .world
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fact.predicate)
                    .font(.headline.monospaced())
                if worldOnly {
                    Text("world only")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .glassEffect(.regular.tint(.gray.opacity(0.25)), in: .capsule)
                }
                Spacer()
                Text("\(fact.producer.kind) \(fact.producer.id)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let target = WorldFacts.link(in: fact.value) {
                Button(target.rawValue) { store.chosenEntity = target }
                    .buttonStyle(.link)
                    .font(.system(.body, design: .monospaced))
            } else {
                Text(describe(fact.value))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
            HStack(spacing: 8) {
                Text(fact.epistemic.type.rawValue)
                Text("since \(fact.validFrom, format: .dateTime.month().day().hour().minute())")
                if let until = fact.validTo {
                    Text("until \(until, format: .dateTime.month().day().hour().minute())")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .foregroundStyle(worldOnly ? .secondary : .primary)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { scried = .fact(fact) }
        .contextMenu {
            Button("Forget", systemImage: "eraser") {
                Task { await store.forget(fact.subjectID, fact.predicate) }
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
            String(decoding: (try? WorldJSON.makeEncoder().encode(value)) ?? Data(), as: UTF8.self)
        }
    }
}
