import Foundation

/// Who April is talking to, and how. "@Beaky …" is a whisper: a word with that bird alone.
/// "Beaky, …" calls her name across the room: she answers first, and the others may chime in.
/// Anything else is for the room, and the lead answers first.
public struct Addressee: Hashable, Sendable {
    public var characterID: EntityID
    /// April singled this character out (`@name`); the message is theirs alone and no scene
    /// opens for it.
    public var alone: Bool

    public init(characterID: EntityID, alone: Bool) {
        self.characterID = characterID
        self.alone = alone
    }
}

/// A world rule, not an app rule, so typed words and (later) spoken ones are addressed the
/// same way.
public protocol AddresseeResolving: Sendable {
    /// `hinted` is what the sender thought (the app's default); the world may know better.
    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> Addressee
}

/// The world before the flock: whoever the sender said, and nobody else.
public struct HintedAddresseeResolver: AddresseeResolving {
    public init() {}
    public func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws
        -> Addressee
    {
        Addressee(characterID: hinted, alone: true)
    }
}

/// The leadership rule: a character named at the start of the message ("Mango, …",
/// "Hey Kenny …") who is present answers first; "@caroll …" is for Caroll alone; otherwise
/// the lead answers first.
public struct LeadAddresseeRule: Sendable {
    public let lead: EntityID

    public init(lead: EntityID) {
        self.lead = lead
    }

    /// `present` maps a spoken name ("mango") to the character it belongs to.
    public func addressee(in text: String, present: [String: EntityID]) -> Addressee {
        let lowered = text.lowercased()
        // The first few words, with greetings dropped: "hey mango," → "mango".
        let openers: Set<String> = ["hey", "hi", "hello", "ok", "okay", "so", "well", "um"]
        let words = lowered.split(whereSeparator: { !$0.isLetter && $0 != "@" }).map(String.init)
        for word in words.prefix(3) {
            let whispered = word.hasPrefix("@")
            let name = whispered ? String(word.dropFirst()) : word
            if let character = present[name] {
                return Addressee(characterID: character, alone: whispered)
            }
            if !openers.contains(name) {
                break
            }
        }
        return Addressee(characterID: lead, alone: false)
    }
}
