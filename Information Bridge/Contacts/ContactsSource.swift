import Contacts
import Foundation
import WorldCore

/// Step 3 of the plan: April's address book. A card becomes a person in the world only when April
/// maps it to an entity here; unmapped cards are never cast. The map and what was last cast
/// live on this Mac; a changed card re-casts what changed, an unmapped one takes its facts back.
actor ContactsSource {
    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void
    typealias Read = @Sendable () async throws -> [ContactCard]

    static let sourceName = "contacts"
    static let interval: Duration = .seconds(3_600)

    private let read: Read
    private let cast: Cast
    private let mapFile: URL
    private let memoryFile: URL
    private(set) var cards: [ContactCard] = []
    private(set) var map: [String: ContactMapping] = [:]
    /// What was last cast, per card: predicate → value, so only changes are sent; and on which
    /// entity, so an unmapped card's facts can be found and taken back.
    private var lastCast: [String: [String: WorldJSONValue]] = [:]
    private var lastEntity: [String: EntityID] = [:]

    private struct Memory: Codable {
        var cast: [String: [String: WorldJSONValue]]
        var entities: [String: EntityID]
    }
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?

    init(
        directory: URL, read: @escaping Read = ContactsSource.readFromContacts,
        cast: @escaping Cast
    ) {
        self.read = read
        self.cast = cast
        mapFile = directory.appending(path: "contacts-map.json")
        memoryFile = directory.appending(path: "contacts-last-cast.json")
        let decoder = WorldJSON.makeDecoder()
        if let data = try? Data(contentsOf: mapFile),
            let saved = try? decoder.decode([String: ContactMapping].self, from: data)
        {
            map = saved
        }
        if let data = try? Data(contentsOf: memoryFile),
            let saved = try? decoder.decode(Memory.self, from: data)
        {
            lastCast = saved.cast
            lastEntity = saved.entities
        }
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

    /// April's word on a card. A mapping removed takes the person's facts back.
    func setMapping(_ mapping: ContactMapping?, for identifier: String) async {
        if let mapping {
            map[identifier] = mapping
        } else {
            map[identifier] = nil
        }
        try? WorldJSON.makeEncoder().encode(map).write(to: mapFile, options: .atomic)
        await castChanges(now: Date())
    }

    /// Reads the address book and casts what changed.
    func poll(now: Date = Date()) async {
        do {
            cards = try await read()
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
        var cast = 0
        // Mapped cards: cast what changed, take back what went away.
        for (identifier, mapping) in map {
            guard let card = byIdentifier[identifier] else { continue }
            // Mapped to someone else now: everything on the old entity is taken back first.
            if let before = lastEntity[identifier], before != mapping.entityID {
                for predicate in (lastCast[identifier] ?? [:]).keys {
                    _ = await retract(
                        subject: before, predicate: predicate, identifier: identifier, now: now)
                }
                lastCast[identifier] = nil
            }
            let wanted = Dictionary(
                uniqueKeysWithValues: ContactFacts.facts(from: card, mapping: mapping)
                    .map { ($0.predicate, $0.value) })
            let had = lastCast[identifier] ?? [:]
            for (predicate, value) in wanted where had[predicate] != value {
                if await send(
                    subject: mapping.entityID, predicate: predicate, value: value,
                    identifier: identifier, now: now)
                {
                    cast += 1
                    lastCast[identifier, default: [:]][predicate] = value
                }
            }
            for predicate in had.keys where wanted[predicate] == nil {
                if await retract(
                    subject: mapping.entityID, predicate: predicate, identifier: identifier,
                    now: now)
                {
                    lastCast[identifier]?[predicate] = nil
                }
            }
        }
        // Cards no longer mapped (or no longer in the book): take everything back.
        for (identifier, had) in lastCast
        where map[identifier] == nil || byIdentifier[identifier] == nil {
            guard let entity = lastEntity[identifier] ?? map[identifier]?.entityID else {
                lastCast[identifier] = nil
                continue
            }
            var remaining = had
            for predicate in had.keys {
                if await retract(
                    subject: entity, predicate: predicate, identifier: identifier, now: now)
                {
                    remaining[predicate] = nil
                }
            }
            lastCast[identifier] = remaining.isEmpty ? nil : remaining
        }
        for (identifier, mapping) in map { lastEntity[identifier] = mapping.entityID }
        try? WorldJSON.makeEncoder().encode(Memory(cast: lastCast, entities: lastEntity)).write(
            to: memoryFile, options: .atomic)
        if cast > 0 {
            status.note = "\(cast) fact\(cast == 1 ? "" : "s") changed"
        }
    }

    private func send(
        subject: EntityID, predicate: String, value: WorldJSONValue, identifier: String, now: Date
    ) async -> Bool {
        do {
            try await cast(
                try BridgeFacts.given(
                    subject: subject, predicate: predicate, value: value, validFor: nil,
                    source: Self.sourceName,
                    itemID: "\(identifier):\(predicate):\(WorldJSON.timestamp(now))", at: now))
            return true
        } catch {
            status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now)
            return false
        }
    }

    private func retract(subject: EntityID, predicate: String, identifier: String, now: Date)
        async -> Bool
    {
        do {
            try await cast(
                try BridgeFacts.given(
                    subject: subject, predicate: predicate, value: .null, validFor: 1,
                    source: Self.sourceName,
                    itemID: "\(identifier):\(predicate):gone:\(WorldJSON.timestamp(now))", at: now))
            return true
        } catch {
            status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now)
            return false
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
            CNContactBirthdayKey, CNContactRelationsKey,
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
                    birthday: contact.birthday, relations: relations))
        }
        return cards
    }
}

enum ContactsFailure: Error, CustomStringConvertible {
    case denied
    var description: String {
        "Information Bridge may not read Contacts (System Settings → Privacy & Security → Contacts)"
    }
}
