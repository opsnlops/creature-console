import CreatureAppSupport
import SwiftUI
import WorldCore

/// April's map from address-book cards to the world's people. A card becomes a person only
/// when she says which one; the rest of the address book stays on the Mac, unread by anyone.
struct PeopleView: View {
    @Bindable var store: BridgeStore
    @State private var search = ""

    private var shown: [ContactCard] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all = store.contacts.sorted {
            ($0.familyName, $0.givenName) < ($1.familyName, $1.givenName)
        }
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.fullName.lowercased().contains(needle) || $0.nickname.lowercased().contains(needle)
                || $0.organization.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search the address book", text: $search)
                    .textFieldStyle(.roundedBorder)
                Text("\(store.contactMap.count) of \(store.contacts.count) mapped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            if store.contacts.isEmpty {
                ContentUnavailableView(
                    "No cards yet", systemImage: "person.crop.rectangle.stack",
                    description: Text(
                        "Turn the Address Book source on in Settings and allow Contacts when macOS asks."
                    ))
            } else {
                List(shown, id: \.identifier) { card in
                    PersonRow(card: card, store: store)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .navigationTitle("People")
    }
}

private struct PersonRow: View {
    let card: ContactCard
    let store: BridgeStore
    @State private var entity = ""
    @State private var relationship = ""
    @FocusState private var editing: Bool

    private var mapping: ContactMapping? { store.contactMap[card.identifier] }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.fullName.isEmpty ? card.organization : card.fullName)
                    .font(.headline)
                Text(
                    [card.nickname, card.organization, card.phones.values.first ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)
            TextField("person:…", text: $entity)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($editing)
                .onSubmit(commit)
                .frame(width: 200)
            TextField("what they are to April", text: $relationship)
                .textFieldStyle(.roundedBorder)
                .focused($editing)
                .onSubmit(commit)
            if mapping != nil {
                Button("Unmap", systemImage: "xmark.circle") {
                    entity = ""
                    relationship = ""
                    Task { await store.setContactMapping(nil, for: card.identifier) }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else if !store.suggestedEntity(for: card).isEmpty, entity.isEmpty {
                Button("Use \(store.suggestedEntity(for: card))") {
                    entity = store.suggestedEntity(for: card)
                    commit()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
        .onAppear {
            entity = mapping?.entityID.rawValue ?? ""
            relationship = mapping?.relationship ?? ""
        }
        .onChange(of: editing) { _, focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        let raw = entity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rel = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let id = EntityID(rawValue: raw), raw.hasPrefix("person:") else {
            store.lastError = ErrorAlert(
                title: "Not a person", message: "People look like person:jesse.")
            return
        }
        let new = ContactMapping(entityID: id, relationship: rel.isEmpty ? nil : rel)
        guard new != mapping else { return }
        Task { await store.setContactMapping(new, for: card.identifier) }
    }
}
