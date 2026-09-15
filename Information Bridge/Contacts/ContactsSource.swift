import Contacts
import Foundation
import WorldCore

/// Step 3 of the plan: April's address book. A card becomes a person in the world only when it
/// says which one - its "Beaky" field, written from the People window or by hand in Contacts;
/// unmapped cards are never cast. The map is the address book's; only what was last cast lives
/// on this Mac. A changed card re-casts what changed, an unmapped one takes its facts back.
actor ContactsSource {
    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void
    typealias Read = @Sendable () async throws -> [ContactCard]
    /// Writes a card's "Beaky" field; nil clears it.
    typealias Write = @Sendable (_ identifier: String, _ value: String?) async throws -> Void

    static let sourceName = "contacts"
    static let interval: Duration = .seconds(3_600)

    private let read: Read
    private let write: Write
    private let cast: Cast
    /// Where the map lived before it moved onto the cards; carried over once, then set aside.
    private let oldMapFile: URL
    private let ledger: FactLedger
    private(set) var cards: [ContactCard] = []
    private(set) var map: [String: ContactMapping] = [:]
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?

    init(
        directory: URL, read: @escaping Read = ContactsSource.readFromContacts,
        write: @escaping Write = ContactsSource.writeToContacts,
        cast: @escaping Cast
    ) {
        self.read = read
        self.write = write
        self.cast = cast
        oldMapFile = directory.appending(path: "contacts-map.json")
        ledger = FactLedger(source: Self.sourceName, directory: directory)
    }

    func start() {
        guard worker == nil else { return }
        worker = Task {
            while !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        status.state = .off
        publish()
    }

    func updates() -> AsyncStream<SourceStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { _ in Task { await self.forget(id) } }
        }
    }

    private func forget(_ id: UUID) { observers[id] = nil }

    /// April's word on a card, written onto the card. A mapping removed takes the person's
    /// facts back.
    func setMapping(_ mapping: ContactMapping?, for identifier: String) async throws {
        try await write(identifier, mapping?.cardValue)
        cards = try await read()
        readMap()
        await castChanges(now: Date())
        status.note = "\(map.count) of \(cards.count) people mapped"
        publish()
    }

    /// The map is whatever the cards say.
    private func readMap() {
        map = Dictionary(
            uniqueKeysWithValues: cards.compactMap { card in
                card.link.flatMap(ContactMapping.init(cardValue:)).map { (card.identifier, $0) }
            })
    }

    /// A map from before the cards carried their own: written onto the cards that have no word
    /// yet, then the file set aside so this runs once.
    private func carryOverOldMap() async throws {
        guard let data = try? Data(contentsOf: oldMapFile),
            let saved = try? WorldJSON.makeDecoder().decode(
                [String: ContactMapping].self, from: data)
        else { return }
        var written = 0
        for (identifier, mapping) in saved {
            guard let card = cards.first(where: { $0.identifier == identifier }), card.link == nil
            else { continue }
            try await write(identifier, mapping.cardValue)
            written += 1
        }
        try FileManager.default.moveItem(
            at: oldMapFile, to: oldMapFile.deletingPathExtension().appendingPathExtension("moved"))
        if written > 0 { cards = try await read() }
    }

    /// Reads the address book and casts what changed.
    func poll(now: Date = Date()) async {
        do {
            cards = try await read()
            try await carryOverOldMap()
            readMap()
            await castChanges(now: now)
            status = SourceStatus(
                state: .on, lastRunAt: now,
                note: "\(map.count) of \(cards.count) people mapped")
        } catch {
            status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now)
        }
        publish()
    }

    private func castChanges(now: Date) async {
        let byIdentifier = Dictionary(uniqueKeysWithValues: cards.map { ($0.identifier, $0) })
        var wanted: [String: FactLedger.Wanted] = [:]
        for (identifier, mapping) in map {
            guard let card = byIdentifier[identifier] else { continue }
            wanted[identifier] = FactLedger.Wanted(
                entityID: mapping.entityID,
                facts: Dictionary(
                    uniqueKeysWithValues: ContactFacts.facts(from: card, mapping: mapping)
                        .map { ($0.predicate, $0.value) }),
                validUntil: nil)
        }
        let cast = await ledger.reconcile(wanted, now: now, cast: cast)
        if cast > 0 {
            status.note = "\(cast) fact\(cast == 1 ? "" : "s") changed"
        }
    }

    private func publish() {
        for observer in observers.values { observer.yield(status) }
    }

    /// The Contacts framework, for real, under its own permission.
    static func readFromContacts() async throws -> [ContactCard] {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else { throw ContactsFailure.denied }
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactNicknameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey,
            CNContactBirthdayKey, CNContactRelationsKey, CNContactUrlAddressesKey,
        ].map { $0 as CNKeyDescriptor }
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .familyName
        var cards: [ContactCard] = []
        let formatter = CNPostalAddressFormatter()
        try store.enumerateContacts(with: request) { contact, _ in
            func label(_ raw: String?) -> String {
                raw.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "other"
            }
            var phones: [String: String] = [:]
            for value in contact.phoneNumbers {
                phones[label(value.label)] = value.value.stringValue
            }
            var emails: [String: String] = [:]
            for value in contact.emailAddresses { emails[label(value.label)] = String(value.value) }
            var addresses: [String: String] = [:]
            for value in contact.postalAddresses {
                addresses[label(value.label)] = formatter.string(from: value.value)
                    .replacingOccurrences(of: "\n", with: ", ")
            }
            var relations: [String: String] = [:]
            for value in contact.contactRelations {
                relations[label(value.label)] = value.value.name
            }
            cards.append(
                ContactCard(
                    identifier: contact.identifier, givenName: contact.givenName,
                    familyName: contact.familyName, nickname: contact.nickname,
                    organization: contact.organizationName, jobTitle: contact.jobTitle,
                    phones: phones, emails: emails, addresses: addresses,
                    birthday: contact.birthday, relations: relations,
                    link: contact.urlAddresses.first(where: isBeakyField).map { String($0.value) }
                ))
        }
        return cards
    }

    private static func isBeakyField(_ value: CNLabeledValue<NSString>) -> Bool {
        value.label?.caseInsensitiveCompare(ContactMapping.label) == .orderedSame
    }

    /// Writes the "Beaky" field on one card - the one field the Bridge ever changes.
    static func writeToContacts(identifier: String, value: String?) async throws {
        let store = CNContactStore()
        let contact = try store.unifiedContact(
            withIdentifier: identifier, keysToFetch: [CNContactUrlAddressesKey as CNKeyDescriptor])
        guard let mutable = contact.mutableCopy() as? CNMutableContact else {
            throw ContactsFailure.notEditable
        }
        var urls = mutable.urlAddresses.filter { !isBeakyField($0) }
        if let value {
            urls.append(CNLabeledValue(label: ContactMapping.label, value: value as NSString))
        }
        mutable.urlAddresses = urls
        let request = CNSaveRequest()
        request.update(mutable)
        try store.execute(request)
    }
}

enum ContactsFailure: Error, CustomStringConvertible {
    case denied
    case notEditable
    var description: String {
        switch self {
        case .denied:
            "Information Bridge may not read Contacts (System Settings → Privacy & Security → Contacts)"
        case .notEditable:
            "that card cannot be changed"
        }
    }
}
