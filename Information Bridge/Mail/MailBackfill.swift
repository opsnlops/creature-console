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
    /// inbox. Runs on the main thread, as AppleScript wants.
    @MainActor
    static func fetch(senders: [String], now: Date = Date()) throws -> [MailMessage] {
        let since = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let sinceText = Self.appleScriptDate(since)
        let separator = "\u{1F}"
        let record = "\u{1E}"
        let senderList = senders.map { "\"\($0)\"" }.joined(separator: ", ")
        let script = """
            set sinceDate to date "\(sinceText)"
            set senderList to {\(senderList)}
            set out to ""
            tell application "Mail"
                repeat with acct in accounts
                    repeat with box in mailboxes of acct
                        if name of box is "INBOX" or name of box is "Inbox" then
                            set recent to (messages of box whose date received > sinceDate)
                            repeat with m in recent
                                set snd to sender of m
                                set hit to false
                                repeat with s in senderList
                                    if snd contains s then set hit to true
                                end repeat
                                if hit then
                                    set out to out & (id of m as string) & "\(separator)" & snd & "\(separator)" & (subject of m) & "\(separator)" & ((date received of m) as «class isot» as string) & "\(separator)" & (content of m) & "\(record)"
                                end if
                            end repeat
                        end if
                    end repeat
                end repeat
            end tell
            return out
            """
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { throw Failure.script("bad script") }
        let result = apple.executeAndReturnError(&error)
        if let error {
            throw Failure.script(error[NSAppleScript.errorMessage] as? String ?? "\(error)")
        }
        let text = result.stringValue ?? ""
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return text.split(separator: Character(record), omittingEmptySubsequences: true).compactMap
        {
            let parts = $0.split(
                separator: Character(separator), maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5 else { return nil }
            let date = formatter.date(from: String(parts[3])) ?? now
            return MailMessage(
                identifier: "mail:" + String(parts[0]), from: String(parts[1]),
                subject: String(parts[2]), date: date, text: String(parts[4]))
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
