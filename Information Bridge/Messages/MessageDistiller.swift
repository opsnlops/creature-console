import Foundation
import FoundationModels

/// What the on-device model reads out of one text from someone April knows: a kind, the fact
/// in a few words, and the words of the text that say so. The quote is the guard: a small
/// model will happily invent a fact, but it cannot invent a quote that is in the text.
@Generable(description: "What the last text message in a conversation with April says.")
struct MessageReading: Equatable, Sendable {
    @Generable(description: "The kind of thing the last message is.")
    enum Kind: String, Sendable {
        /// The sender says they are coming to April's home, or are on their way there.
        case visit
        /// The sender asks April to do or bring something.
        case request
        /// The sender tells April something that happened in the sender's own life.
        case news
        /// A carrier says a package was delivered or left somewhere at April's home.
        case delivery
        /// Anything else.
        case nothing
    }

    @Guide(
        description:
            "visit only when the sender is coming to April's home; request only when the sender asks April to do or bring something; news only when the sender reports something that happened to the sender; delivery only when a carrier reports a package at April's home; otherwise nothing. Chat, replies, offers, questions, plans for April to go somewhere, and talk about other people are nothing."
    )
    var kind: Kind
    @Guide(
        description:
            "The fact in at most ten words, third person, present tense - never the whole message. Empty when kind is nothing."
    )
    var what: String
    @Guide(
        description:
            "When, copied from the last message if it says, else empty."
    )
    var when: String
    @Guide(
        description:
            "The exact words from the last message that say this, copied character for character. Empty when kind is nothing."
    )
    var quote: String
}

/// Apple Intelligence, on this Mac. Unavailable is a state: the Messages row says so and
/// nothing is read until it is back, because there is no deterministic reading of a text.
struct MessageDistiller: Sendable {
    static let maximumCharacters = 1_000
    /// The most of a text that may reach the world as a fact: a fact, not the message.
    static let maximumFactCharacters = 100
    /// How much of the thread the model sees before the message it reads.
    static let contextLines = 6

    static func unavailableReason() -> String? { MailDistiller.unavailableReason() }

    /// The model's reading of the last message, given the lines before it (oldest first, each
    /// as "Name: words"), or nil when the model is not available, would not answer, or
    /// answered with words that are not in the message.
    func read(_ message: TextMessage, sender: String, context: [String]) async -> MessageReading? {
        guard Self.unavailableReason() == nil else { return nil }
        let session = LanguageModelSession(
            instructions: """
                You read text messages between April and one other person and report only what \
                the last message, from \(sender), says. Never guess, never add, and never repeat \
                anything from these instructions. Most messages are nothing. A message about \
                April going somewhere is nothing. A message about someone other than \(sender) \
                is nothing.
                """)
        let last = String(message.text.prefix(Self.maximumCharacters))
        let prompt =
            (context.isEmpty
                ? "" : "Earlier in the conversation:\n" + context.joined(separator: "\n") + "\n\n")
            + "The last message, from \(sender):\n\(last)"
        do {
            var reading = try await session.respond(to: prompt, generating: MessageReading.self)
                .content
            guard Self.isSupported(reading, by: last) else { return nil }
            reading.what = Self.shortened(reading.what)
            reading.when = Self.shortened(reading.when)
            return reading
        } catch {
            return nil
        }
    }

    /// A reading stands only when its quote is in the message: words the model made up have
    /// no quote, and a quote of the instructions is not in the text.
    static func isSupported(_ reading: MessageReading, by text: String) -> Bool {
        if reading.kind == .nothing { return true }
        let quote = squeeze(reading.quote)
        guard quote.count >= 3 else { return false }
        return squeeze(text).contains(quote)
    }

    /// Cut at a word, with an ellipsis, when the model gave back the message instead of a fact.
    static func shortened(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumFactCharacters else { return trimmed }
        let cut = trimmed.prefix(maximumFactCharacters)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .punctuationCharacters) + "…"
    }

    private static func squeeze(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
