import CreatureAppSupport
import Foundation
import SwiftMail

/// One IMAP account the Bridge reads: April's own server first, iCloud second. The password
/// lives in the Keychain; everything else in defaults. No Mail.app in the loop.
struct IMAPAccount: Equatable, Sendable, Codable, Identifiable {
    var id: String { "\(username)@\(host)" }
    var host: String
    var port: Int = 993
    var username: String
    /// Mailboxes to read; empty means every mailbox but the outgoing and the discarded.
    var mailboxes: [String] = []

    static let skippedMailboxes: Set<String> = [
        "Drafts", "Sent", "Sent Messages", "Sent Mail", "Outbox", "Trash", "Deleted Messages",
        "Junk", "Spam", "Junk E-mail", "Junk Email",
    ]
}

/// Passwords in the Creature family's shared Keychain, one item per account, synchronizable:
/// typed on this Mac, there on the laptop.
enum IMAPPasswords {
    static let service = "io.opsnlops.Information-Bridge.imap"

    static func password(for account: IMAPAccount) -> String? {
        try? CreatureKeychainItem(service: service, account: account.id).value()
    }

    static func set(_ password: String, for account: IMAPAccount) throws {
        try CreatureKeychainItem(service: service, account: account.id)
            .set(password.isEmpty ? nil : password)
    }
}

enum IMAPIntakeFailure: Error, CustomStringConvertible {
    case noPassword(String)

    var description: String {
        switch self {
        case .noPassword(let account): "no password for \(account) - set one in Settings"
        }
    }
}

/// Reads an account: every allowed mailbox, messages since a date from the listed senders,
/// as `MailMessage`s. The first read goes back 120 days; later ones ask only for UIDs newer
/// than the last seen in each mailbox, remembered on this Mac.
actor IMAPIntake {
    struct Progress: Equatable, Sendable {
        var mailboxes = 0
        var messages = 0
    }

    private let account: IMAPAccount
    private let senders: [String]
    private let stateFile: URL
    /// Last UID seen per mailbox, with the UIDVALIDITY it was seen under.
    private var lastSeen: [String: LastSeen] = [:]

    private struct LastSeen: Codable, Equatable {
        var uidValidity: UInt32?
        var uid: UInt32
    }

    init(account: IMAPAccount, senders: [String], directory: URL) {
        self.account = account
        self.senders = senders
        stateFile = directory.appending(
            path: "imap-\(account.id.filter { $0.isLetter || $0.isNumber || $0 == "." })-seen.json")
        if let data = try? Data(contentsOf: stateFile),
            let saved = try? JSONDecoder().decode([String: LastSeen].self, from: data)
        {
            lastSeen = saved
        }
    }

    /// The account's mailboxes, for the settings list.
    static func mailboxes(of account: IMAPAccount) async throws -> [String] {
        guard let password = IMAPPasswords.password(for: account) else {
            throw IMAPIntakeFailure.noPassword(account.id)
        }
        let server = IMAPServer(host: account.host, port: account.port)
        try await server.connect()
        defer { Task { try? await server.disconnect() } }
        try await server.login(username: account.username, password: password)
        return try await server.listMailboxes().map(\.name).sorted()
    }

    /// Everything new from the listed senders: the last `days` on a first read of a mailbox,
    /// newer than the last seen afterwards. `progress` is told as each mailbox is done.
    func read(
        since days: Int, now: Date = Date(),
        progress: @Sendable (Progress) async -> Void = { _ in }
    ) async throws -> [MailMessage] {
        guard let password = IMAPPasswords.password(for: account) else {
            throw IMAPIntakeFailure.noPassword(account.id)
        }
        let server = IMAPServer(host: account.host, port: account.port)
        try await server.connect()
        defer { Task { try? await server.disconnect() } }
        try await server.login(username: account.username, password: password)
        let names: [String]
        if account.mailboxes.isEmpty {
            names = try await server.listMailboxes().map(\.name).filter {
                !IMAPAccount.skippedMailboxes.contains($0)
                    && !IMAPAccount.skippedMailboxes.contains(
                        String($0.split(separator: "/").last ?? ""))
            }
        } else {
            names = account.mailboxes
        }
        var messages: [MailMessage] = []
        var done = Progress()
        for name in names {
            let selection = try await server.selectMailbox(name)
            let validity: UInt32? = selection.uidValidity.value
            var seen = lastSeen[name]
            if let seen, let validity, seen.uidValidity != validity {
                // The server renumbered: start this mailbox over.
                lastSeen[name] = nil
            }
            seen = lastSeen[name]
            var criteria: [SearchCriteria] = [
                .since(now.addingTimeInterval(-TimeInterval(days) * 86_400))
            ]
            if !senders.isEmpty {
                var clause = SearchCriteria.from(senders[0])
                for sender in senders.dropFirst() { clause = .or(.from(sender), clause) }
                criteria.append(clause)
            }
            let found: MessageIdentifierSet<UID> =
                if let seen {
                    try await server.search(
                        identifierSet: MessageIdentifierSet<UID>(Int(seen.uid + 1)...),
                        criteria: criteria)
                } else {
                    try await server.search(criteria: criteria)
                }
            var newest = seen?.uid ?? 0
            if !found.isEmpty {
                let infos = try await server.fetchMessageInfosBulk(using: found)
                for info in infos {
                    guard let uid = info.uid else { continue }
                    newest = max(newest, UInt32(uid.value))
                    let message = try await server.fetchMessage(from: info)
                    let text = message.textBody ?? MailText.plain(fromHTML: message.htmlBody ?? "")
                    messages.append(
                        MailMessage(
                            identifier: "mail:"
                                + (info.messageId.map { "\($0.localPart)@\($0.domain)" }
                                    ?? "\(account.id)/\(name)/\(uid.value)"),
                            from: info.from ?? "", subject: info.subject ?? "",
                            date: info.date ?? now, text: text))
                }
            }
            lastSeen[name] = LastSeen(uidValidity: validity, uid: newest)
            done.mailboxes += 1
            done.messages = messages.count
            await progress(done)
        }
        try? JSONEncoder().encode(lastSeen).write(to: stateFile, options: .atomic)
        return messages
    }
}

/// HTML to readable text, for the mails that have no plain part.
enum MailText {
    static func plain(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>|<script[^>]*>[\\s\\S]*?</script>", with: " ",
            options: .regularExpression)
        text = text.replacingOccurrences(
            of: "<br\\s*/?>|</p>|</div>|</tr>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
