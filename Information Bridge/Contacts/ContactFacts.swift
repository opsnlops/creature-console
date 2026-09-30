import Foundation
import WorldCore

/// One address-book card, as plain values - the Contacts framework's answer without its types,
/// so the turning into facts is testable anywhere.
struct ContactCard: Equatable, Sendable, Codable {
    var identifier: String
    var givenName: String
    var familyName: String
    var nickname: String
    var organization: String
    var jobTitle: String
    /// Label → number, in the card's own labels ("mobile", "home", "work").
    var phones: [String: String]
    var emails: [String: String]
    /// Label → one-line address.
    var addresses: [String: String]
    /// Month and day, and the year when the card has one.
    var birthday: DateComponents?
    /// Label → name, from the card's related names ("sister", "spouse").
    var relations: [String: String]
    /// The card's own word on who it is in the world: the URL labeled "Beaky", as written.
    var link: String? = nil

    var fullName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// April's word on a card: which entity it is, and, if she says so, what the person is to her.
/// It lives on the card itself, as a URL labeled "Beaky" - `person:jesse; general contractor` -
/// so it syncs with the address book, can be edited in Contacts on any device, and goes with
/// the Bridge wherever it runs. The People window reads and writes that field; nothing else
/// remembers it.
struct ContactMapping: Equatable, Sendable, Codable {
    static let label = "Beaky"

    var entityID: EntityID
    var relationship: String?
    /// "she/her", "they/them" - Contacts keeps a card's own pronouns encrypted, out of reach
    /// of any app, so April writes them here.
    var pronouns: String?

    init(entityID: EntityID, relationship: String? = nil, pronouns: String? = nil) {
        self.entityID = entityID
        self.relationship = relationship
        self.pronouns = pronouns
    }

    /// From the card's field: "person:jesse", "person:jesse; general contractor", or with
    /// pronouns after either - "person:natty; friend; they/them", "person:natty; they/them".
    /// A part is pronouns when it is pronoun words joined by slashes, or starts
    /// "pronouns:"; the other part is the relationship. Anything that is not a person is no
    /// mapping.
    init?(cardValue: String) {
        let parts = cardValue.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let raw = parts.first?.lowercased(), raw.hasPrefix("person:"),
            let id = EntityID(rawValue: raw)
        else { return nil }
        entityID = id
        var relationship: [String] = []
        for part in parts.dropFirst() where !part.isEmpty {
            if pronouns == nil, let said = Self.pronouns(in: part) {
                pronouns = said
            } else {
                relationship.append(part)
            }
        }
        self.relationship = relationship.isEmpty ? nil : relationship.joined(separator: "; ")
    }

    /// What goes on the card.
    var cardValue: String {
        ([entityID.rawValue] + [relationship, pronouns].compactMap { $0 }).joined(separator: "; ")
    }

    /// Words that are pronouns, so "they/them" is read as pronouns and "friend/neighbor" as
    /// what someone is to April.
    static let pronounWords: Set<String> = [
        "she", "her", "hers", "herself", "he", "him", "his", "himself", "they", "them", "their",
        "theirs", "themself", "themselves", "it", "its", "xe", "xem", "xyr", "xyrs", "ze", "zir",
        "zirs", "hir", "hirs", "ey", "em", "eir", "eirs", "fae", "faer", "faers", "any", "all",
    ]

    /// "they/them" from "They / Them"; the words after "pronouns:" whatever they are; nil
    /// when the part is not pronouns.
    static func pronouns(in part: String) -> String? {
        let lower = part.lowercased()
        if lower.hasPrefix("pronouns:") {
            let said = part.dropFirst("pronouns:".count).trimmingCharacters(in: .whitespaces)
            return said.isEmpty ? nil : said
        }
        let words = lower.split(separator: "/").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard words.count >= 2, words.allSatisfy({ pronounWords.contains($0) }) else {
            return nil
        }
        return words.joined(separator: "/")
    }
}

/// One fact the Bridge will cast about a person.
struct ContactFact: Equatable, Sendable {
    var predicate: String
    var value: WorldJSONValue
}

/// The facts a card makes, on the person April mapped it to. The whole card is stored - April:
/// "address book entries, too" - and the glossary's audience keeps the private parts with the
/// world: numbers, addresses, and emails never reach a prompt unless April flips them.
enum ContactFacts {
    static let worldOnly: Set<String> = ["contact.phone", "contact.email", "contact.address"]

    static let meanings: [String: String] = [
        "contact.name": "the person's full name as it appears in April's address book",
        "contact.nickname": "what the person goes by, from April's address book",
        "contact.phone": "the person's phone numbers, by label, from April's address book",
        "contact.email": "the person's email addresses, by label, from April's address book",
        "contact.address": "where the person lives or works, by label, from April's address book",
        "contact.organization": "the company or group the person belongs to",
        "contact.job_title": "what the person does for work",
        "contact.birthday":
            "the person's birthday, as a month and day (and year if April's address book has it)",
        "person.relationship":
            "what the person is to April - her sister, her contractor - in her own words",
    ]

    static func facts(from card: ContactCard, mapping: ContactMapping) -> [ContactFact] {
        var facts: [ContactFact] = []
        if !card.fullName.isEmpty {
            facts.append(ContactFact(predicate: "contact.name", value: .string(card.fullName)))
        }
        if !card.nickname.isEmpty {
            facts.append(ContactFact(predicate: "contact.nickname", value: .string(card.nickname)))
        }
        if !card.phones.isEmpty {
            facts.append(ContactFact(predicate: "contact.phone", value: labelled(card.phones)))
        }
        if !card.emails.isEmpty {
            facts.append(ContactFact(predicate: "contact.email", value: labelled(card.emails)))
        }
        if !card.addresses.isEmpty {
            facts.append(
                ContactFact(predicate: "contact.address", value: labelled(card.addresses)))
        }
        if !card.organization.isEmpty {
            facts.append(
                ContactFact(predicate: "contact.organization", value: .string(card.organization)))
        }
        if !card.jobTitle.isEmpty {
            facts.append(ContactFact(predicate: "contact.job_title", value: .string(card.jobTitle)))
        }
        if let birthday = card.birthday, let text = birthdayText(birthday) {
            facts.append(ContactFact(predicate: "contact.birthday", value: .string(text)))
        }
        // April's own word wins over the card's related names.
        let relationship =
            mapping.relationship?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? relationshipFromCard(card)
        if let relationship, !relationship.isEmpty {
            facts.append(
                ContactFact(predicate: "person.relationship", value: .string(relationship)))
        }
        // The world's own word for them, shared with the birds' pronouns: the minds see it
        // beside the name, never as a fact to say.
        if let pronouns = mapping.pronouns, !pronouns.isEmpty {
            facts.append(
                ContactFact(predicate: WorldFacts.pronouns, value: .string(pronouns)))
        }
        return facts
    }

    private static func labelled(_ values: [String: String]) -> WorldJSONValue {
        .object(
            Dictionary(
                uniqueKeysWithValues: values.sorted { $0.key < $1.key }.map {
                    ($0.key, WorldJSONValue.string($0.value))
                }))
    }

    /// "March 4" or "March 4, 1971".
    static func birthdayText(_ components: DateComponents) -> String? {
        guard let month = components.month, let day = components.day, (1...12).contains(month)
        else { return nil }
        let names = [
            "January", "February", "March", "April", "May", "June", "July", "August",
            "September", "October", "November", "December",
        ]
        var text = "\(names[month - 1]) \(day)"
        if let year = components.year, year > 1 {
            text += ", \(year)"
        }
        return text
    }

    /// The card's related names, read the other way round: a card whose relation "sister" is
    /// April makes the person April's sister.
    private static func relationshipFromCard(_ card: ContactCard) -> String? {
        for (label, name) in card.relations.sorted(by: { $0.key < $1.key })
        where name.lowercased().hasPrefix("april") {
            return "April's \(label.lowercased())"
        }
        return nil
    }
}
