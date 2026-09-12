import Foundation

/// Who April is talking to, and whether she said so. Naming a bird is a word with that bird
/// alone — Beaky is April's familiar and she must be able to talk to just her; an unaddressed
/// remark is for the room, and the world may open a scene for it.
public struct Addressee: Hashable, Sendable {
    public var characterID: EntityID
    /// April named this character; the message is theirs alone.
    public var named: Bool

    public init(characterID: EntityID, named: Bool) {
        self.characterID = characterID
        self.named = named
    }
}

/// A world rule, not an app rule, so typed words and (later) spoken ones are addressed the
/// same way.
public protocol AddresseeResolving: Sendable {
    /// `hinted` is what the sender thought (the app's default); the world may know better.
    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> Addressee
}

/// The world before the flock: whoever the sender said, as if named.
public struct HintedAddresseeResolver: AddresseeResolving {
    public init() {}
    public func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws
        -> Addressee
    {
        Addressee(characterID: hinted, named: true)
    }
}

/// The leadership rule: a character named at the start of the message ("Mango, …",
/// "Hey Kenny …", "@caroll …") who is present gets it; otherwise the lead.
public struct LeadAddresseeRule: Sendable {
    public let lead: EntityID

    public init(lead: EntityID) {
        self.lead = lead
    }

    /// `present` maps a spoken name ("mango") to the character it belongs to.
    public func addressee(in text: String, present: [String: EntityID]) -> Addressee {
        let lowered = text.lowercased()
        // The first few words, with greetings and an @ dropped: "hey mango," → "mango".
        let openers: Set<String> = ["hey", "hi", "hello", "ok", "okay", "so", "well", "um"]
        let words = lowered.split(whereSeparator: { !$0.isLetter && $0 != "@" }).map(String.init)
        for word in words.prefix(3) {
            let name = word.hasPrefix("@") ? String(word.dropFirst()) : word
            if let character = present[name] {
                return Addressee(characterID: character, named: true)
            }
            if !openers.contains(name) {
                break
            }
        }
        return Addressee(characterID: lead, named: false)
    }
}
