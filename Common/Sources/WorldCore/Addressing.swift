import Foundation

/// Who April is talking to. A world rule, not an app rule, so typed words and (later) spoken
/// ones are addressed the same way.
public protocol AddresseeResolving: Sendable {
    /// The character the utterance is for. `hinted` is what the sender thought (the app's
    /// default); the world may know better.
    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> EntityID
}

/// The world before the flock: whoever the sender said.
public struct HintedAddresseeResolver: AddresseeResolving {
    public init() {}
    public func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws
        -> EntityID
    {
        hinted
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
    public func addressee(in text: String, present: [String: EntityID]) -> EntityID {
        let lowered = text.lowercased()
        // The first few words, with greetings and an @ dropped: "hey mango," → "mango".
        let openers: Set<String> = ["hey", "hi", "hello", "ok", "okay", "so", "well", "um"]
        let words = lowered.split(whereSeparator: { !$0.isLetter && $0 != "@" }).map(String.init)
        for word in words.prefix(3) {
            let name = word.hasPrefix("@") ? String(word.dropFirst()) : word
            if let character = present[name] {
                return character
            }
            if !openers.contains(name) {
                break
            }
        }
        return lead
    }
}
