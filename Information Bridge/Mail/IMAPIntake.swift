import CreatureAppSupport
import Foundation
import SwiftMail
import os

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

    /// The password, or nil when none was ever set. A Keychain that will not answer - the Mac
    /// locked while April is out, most often - is an error, not an absence.
    static func password(for account: IMAPAccount) throws -> String {
        let item = try CreatureKeychainItem(service: service, account: account.id)
        do {
            guard let password = try item.value() else {
                throw IMAPIntakeFailure.noPassword(account.id)
            }
            return password
        } catch let error as ProxyAPIKeyStoreError {
            throw IMAPIntakeFailure.keychain(account.id, error)
        }
    }

    static func set(_ password: String, for account: IMAPAccount) throws {
        try CreatureKeychainItem(service: service, account: account.id)
            .set(password.isEmpty ? nil : password)
    }

    /// Makes the password readable while the Mac is locked, so the hourly read goes on while
    /// April is out. Called when Mail starts; a password set before this existed is fixed up.
    static func allowReadingWhileLocked(for account: IMAPAccount) throws {
        try CreatureKeychainItem(service: service, account: account.id).allowReadingWhileLocked()
    }
}

enum IMAPIntakeFailure: Error, CustomStringConvertible {
    case noPassword(String)
    case keychain(String, ProxyAPIKeyStoreError)

    var description: String {
        switch self {
        case .noPassword(let account): "no password for \(account) - set one in Settings"
        case .keychain(let account, let error):
            error.isMacLocked
                ? "the Keychain will not give the password for \(account) while the Mac is locked - trying again"
                : "the Keychain will not give the password for \(account): \(error)"
        }
    }
}

/// Reads an account: every allowed mailbox, messages since a date, as `MailMessage`s. The
/// headers of everything new are fetched and offered to `interest`; only the bodies of the
/// messages it wants (orders, shipments, appointments - by sender and subject) are read. The
/// first read goes back 120 days; later ones ask only for UIDs newer than the last seen in
/// each mailbox, remembered on this Mac.
actor IMAPIntake {
    static let log = Logger(subsystem: "io.opsnlops.Information-Bridge", category: "mail")

    struct Progress: Equatable, Sendable {
        var mailboxes = 0
        var messages = 0
    }

    private let account: IMAPAccount
    /// Whether a message, by sender and subject, is worth its body.
    typealias Interest = @Sendable (_ from: String, _ subject: String) -> Bool
    private let interest: Interest
    private let stateFile: URL
    /// Last UID seen per mailbox, with the UIDVALIDITY it was seen under - as committed.
    private var lastSeen: [String: LastSeen] = [:]
    /// What the last read reached, kept until the source says it has taken the messages: a
    /// Bridge stopped mid-way must read them again, not skip them.
    private var pending: [String: LastSeen] = [:]

    private struct LastSeen: Codable, Equatable {
        var uidValidity: UInt32?
        var uid: UInt32
        /// The readers this mailbox was last read with; older is read again.
        var readingVersion: Int? = nil
    }

    init(account: IMAPAccount, interest: @escaping Interest, directory: URL) {
        self.account = account
        self.interest = interest
        stateFile = directory.appending(
            path: "imap-\(account.id.filter { $0.isLetter || $0.isNumber || $0 == "." })-seen.json")
        if let data = try? Data(contentsOf: stateFile),
            let saved = try? JSONDecoder().decode([String: LastSeen].self, from: data)
        {
            lastSeen = saved.filter { $0.value.readingVersion == MailSource.readingVersion }
        }
    }

    /// The account's mailboxes, for the settings list.
    static func mailboxes(of account: IMAPAccount) async throws -> [String] {
        let password = try IMAPPasswords.password(for: account)
        let server = IMAPServer(host: account.host, port: account.port)
        try await server.connect()
        defer { Task { try? await server.disconnect() } }
        try await server.login(username: account.username, password: password)
        return try await server.listMailboxes().map(\.name).sorted()
    }

    /// Everything new that `interest` wants: the last `days` on a first read of a mailbox,
    /// newer than the last seen afterwards. `progress` is told as each mailbox is done. The
    /// checkpoint moves only on `commit()`, once the caller has done with the messages.
    func read(
        since days: Int, now: Date = Date(),
        progress: @Sendable (Progress) async -> Void = { _ in }
    ) async throws -> [MailMessage] {
        let password = try IMAPPasswords.password(for: account)
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
        pending = lastSeen
        for name in names {
            let selection = try await server.selectMailbox(name)
            let validity: UInt32? = selection.uidValidity.value
            var seen = lastSeen[name]
            if let seen, let validity, seen.uidValidity != validity {
                // The server renumbered: start this mailbox over.
                pending[name] = nil
            }
            seen = pending[name]
            let criteria: [SearchCriteria] = [
                .since(now.addingTimeInterval(-TimeInterval(days) * 86_400))
            ]
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
                    // Headers only, for most mail: the body is fetched when the sender and
                    // subject say it is an order, a shipment, or an appointment.
                    guard interest(info.from ?? "", info.subject ?? "") else {
                        Self.log.debug(
                            "Mail: \(name, privacy: .public) uid \(uid.value) from \(info.from ?? "", privacy: .private) \"\(info.subject ?? "", privacy: .private)\" - headers only, not read"
                        )
                        continue
                    }
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
            pending[name] = LastSeen(
                uidValidity: validity, uid: newest, readingVersion: MailSource.readingVersion)
            done.mailboxes += 1
            done.messages = messages.count
            await progress(done)
        }
        return messages
    }

    /// Watches the inbox with IMAP IDLE on a connection of its own, and calls `changed` the
    /// moment the server says a message arrived - the cleaning lady's reply reaches the world
    /// in seconds, not at the next poll. SwiftMail renews the IDLE and reconnects on its
    /// own; a session that ends anyway is begun again after a pause. Cancel the task to stop.
    static let watchedMailbox = "INBOX"

    nonisolated func watchInbox(
        account: IMAPAccount, changed: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task {
            var pause: Duration = .seconds(5)
            while !Task.isCancelled {
                do {
                    let password = try IMAPPasswords.password(for: account)
                    let server = IMAPServer(host: account.host, port: account.port)
                    try await server.connect()
                    try await server.login(username: account.username, password: password)
                    let session = try await server.idle(on: Self.watchedMailbox)
                    Self.log.notice(
                        "Mail: watching \(account.id, privacy: .public) \(Self.watchedMailbox) with IDLE"
                    )
                    pause = .seconds(5)
                    await withTaskCancellationHandler {
                        for await event in session.events {
                            if case .exists = event {
                                Self.log.notice("Mail: the server says new mail arrived")
                                await changed()
                            }
                            if case .bye = event { break }
                        }
                    } onCancel: {
                        Task { try? await session.done() }
                    }
                    try? await server.disconnect()
                } catch {
                    Self.log.error(
                        "Mail: IDLE on \(account.id, privacy: .public) failed - \("\(error)", privacy: .public)"
                    )
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: pause)
                pause = min(pause * 2, .seconds(300))
            }
        }
    }

    /// The messages of the last read are taken: the next read starts after them.
    func commit() {
        lastSeen = pending
        try? JSONEncoder().encode(lastSeen).write(to: stateFile, options: .atomic)
    }
}

/// HTML to readable text, for the mails that have no plain part; and a reply split into the
/// latest words and the quoted thread beneath.
enum MailText {
    /// The newest part of a reply and what it quotes, with the "On <date>, <who> wrote:"
    /// attribution and the `>` markers gone - a date on that line is nobody's appointment.
    static func parts(of text: String) -> (latest: String, quoted: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var cut: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") || trimmed.hasPrefix("-----Original Message")
                || (trimmed.hasPrefix("On ") && trimmed.hasSuffix("wrote:"))
                || (trimmed.hasPrefix("On ") && index + 1 < lines.count
                    && lines[index + 1].trimmingCharacters(in: .whitespaces).hasSuffix("wrote:"))
            {
                cut = index
                break
            }
        }
        guard let cut else { return (text.trimmingCharacters(in: .whitespacesAndNewlines), "") }
        let latest = lines[..<cut].joined(separator: "\n")
        let quoted = lines[cut...].filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !(trimmed.hasPrefix("On ") && trimmed.hasSuffix("wrote:"))
                && !trimmed.hasPrefix("-----Original Message") && !trimmed.hasSuffix("wrote:")
        }.map { line -> String in
            var stripped = Substring(line)
            while let first = stripped.first, first == ">" || first == " " {
                stripped = stripped.dropFirst()
            }
            return String(stripped)
        }.joined(separator: "\n")
        return (
            latest.trimmingCharacters(in: .whitespacesAndNewlines),
            quoted.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

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
