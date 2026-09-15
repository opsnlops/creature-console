import Foundation

/// The one-time backfill: the Mail extension only sees what arrives after it is enabled, so the
/// last 120 days are asked of Mail itself, through its scripting interface, once. macOS asks
/// April once whether the Bridge may control Mail. Only mail from the listed senders is read.
enum MailBackfill {
    static let days = 120

    enum Failure: Error, CustomStringConvertible {
        case script(String)
        var description: String {
            switch self {
            case .script(let message):
                "Mail would not answer the backfill (System Settings → Privacy & Security → Automation): \(message)"
            }
        }
    }

    /// Messages from the last `days` whose sender contains one of `senders`, from every account's
    /// inbox. Mail does the filtering (one `whose` per sender, which it answers quickly) and the
    /// script runs in its own `osascript` process, so the Bridge's window never waits on it.
    static func fetch(senders: [String], now: Date = Date()) async throws -> [MailMessage] {
        let since = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let sinceText = appleScriptDate(since)
        let separator = "\u{1F}"
        let record = "\u{1E}"
        // One `whose` per mailbox with every sender OR'd in: Mail answers each quickly, and
        // April's rules file her mail into folders, so every mailbox but the outgoing and the
        // discarded is searched.
        let senderClause = senders.map { "sender contains \"\($0)\"" }.joined(separator: " or ")
        let script = """
            set sinceDate to date "\(sinceText)"
            set skipped to {"Drafts", "Sent", "Sent Messages", "Sent Mail", "Outbox", "Trash", "Deleted Messages", "Junk", "Spam", "Junk E-mail"}
            set out to ""
            tell application "Mail"
                repeat with acct in accounts
                    repeat with box in mailboxes of acct
                        if (name of box) is not in skipped then
                            set hits to (messages of box whose date received > sinceDate and (\(senderClause)))
                            repeat with m in hits
                                set out to out & (id of m as string) & "\(separator)" & (sender of m) & "\(separator)" & (subject of m) & "\(separator)" & ((date received of m) as «class isot» as string) & "\(separator)" & (content of m) & "\(record)"
                            end repeat
                        end if
                    end repeat
                end repeat
            end tell
            return out
            """
        let text = try await run(script)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var byID: [String: MailMessage] = [:]
        for line in text.split(separator: Character(record), omittingEmptySubsequences: true) {
            let parts = line.split(
                separator: Character(separator), maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5 else { continue }
            let id = "mail:" + String(parts[0])
            byID[id] = MailMessage(
                identifier: id, from: String(parts[1]), subject: String(parts[2]),
                date: formatter.date(from: String(parts[3])) ?? now, text: String(parts[4]))
        }
        return Array(byID.values)
    }

    /// `osascript`, in a child process, off every actor: the Bridge stays responsive while Mail
    /// works, and macOS still asks in the Bridge's name.
    private static func run(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-"]
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { finished in
                let out = String(
                    decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(
                    decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(
                        throwing: Failure.script(
                            err.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(script.utf8))
                try input.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: Failure.script("\(error)"))
            }
        }
    }

    /// AppleScript's date literal in the current locale's long form is unreliable; a month-name
    /// form parses everywhere.
    static func appleScriptDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
        return formatter.string(from: date)
    }
}
