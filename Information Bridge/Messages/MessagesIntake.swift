import Foundation
import SQLite3

/// Messages' own database, `~/Library/Messages/chat.db`, read directly. April, 2026-09-14:
/// "Let's do the dirty thing and look at chat.db. This isn't an app we're going to sell."
/// Opened read-only and `immutable`, so Messages' own writes are never blocked; opened and
/// closed on every read, so nothing is held. Full Disk Access is macOS's price of admission.
struct MessagesIntake: Sendable {
    static let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Messages/chat.db")

    let path: URL

    init(path: URL = MessagesIntake.defaultPath) {
        self.path = path
    }

    static let pageSize = 500

    /// Every message after `rowID` - or, on a first run with no row yet, everything since
    /// `since` - oldest first, all of it. Tapbacks and group-chat housekeeping (someone joined,
    /// the name changed) are not messages and are skipped.
    func read(after rowID: Int64?, since: Date) throws -> [TextMessage] {
        var all: [TextMessage] = []
        var cursor = rowID
        while true {
            let page = try readPage(after: cursor, since: since)
            all += page
            guard page.count == Self.pageSize, let last = page.last else { return all }
            cursor = last.rowID
        }
    }

    private func readPage(after rowID: Int64?, since: Date) throws -> [TextMessage] {
        var db: OpaquePointer?
        let uri = "file:\(path.path)?immutable=1"
        let opened = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        defer { if db != nil { sqlite3_close(db) } }
        guard opened == SQLITE_OK else {
            throw MessagesFailure.cannotOpen(opened, db.map { String(cString: sqlite3_errmsg($0)) })
        }
        let sql = """
            SELECT m.ROWID, m.date, m.is_from_me, m.text, m.attributedBody, h.id,
                   c.chat_identifier, c.style
            FROM message m
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            LEFT JOIN chat_message_join j ON j.message_id = m.ROWID
            LEFT JOIN chat c ON c.ROWID = j.chat_id
            WHERE m.ROWID > ? AND m.date > ? AND m.associated_message_type = 0 AND m.item_type = 0
            ORDER BY m.ROWID
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MessagesFailure.schema(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID ?? 0)
        // A row already seen needs no date test; a first run asks only for the recent past.
        sqlite3_bind_int64(statement, 2, rowID == nil ? Self.raw(from: since) : 0)
        sqlite3_bind_int(statement, 3, Int32(Self.pageSize))
        var messages: [TextMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let row = sqlite3_column_int64(statement, 0)
            let raw = sqlite3_column_int64(statement, 1)
            let fromMe = sqlite3_column_int(statement, 2) == 1
            var text = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            if text.isEmpty, let bytes = sqlite3_column_blob(statement, 4) {
                let length = Int(sqlite3_column_bytes(statement, 4))
                text = Self.text(fromAttributedBody: Data(bytes: bytes, count: length))
            }
            let handle = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            let chat = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
            let style = sqlite3_column_int(statement, 7)
            messages.append(
                TextMessage(
                    rowID: row, handle: handle, isFromMe: fromMe, date: Self.date(from: raw),
                    text: text, chatIdentifier: chat, isGroupChat: style == 43))
        }
        return messages
    }

    /// Messages keeps time as nanoseconds since 2001 (older rows: seconds).
    static func date(from raw: Int64) -> Date {
        let seconds = raw > 100_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    static func raw(from date: Date) -> Int64 {
        Int64(date.timeIntervalSinceReferenceDate * 1_000_000_000)
    }

    /// The words out of an `attributedBody`: an NSAttributedString in Apple's typedstream
    /// archive. The string sits right after the `NSString` class name and a `+` marker, length
    /// first - one byte, or 0x81 and two bytes, or 0x82 and four. Anything else reads as empty.
    static func text(fromAttributedBody data: Data) -> String {
        let bytes = [UInt8](data)
        guard let marker = firstRange(of: Array("NSString".utf8), in: bytes) else { return "" }
        var index = marker
        while index < bytes.count, bytes[index] != 0x2B { index += 1 }
        index += 1
        guard index < bytes.count else { return "" }
        var length = 0
        switch bytes[index] {
        case 0x81:
            guard index + 2 < bytes.count else { return "" }
            length = Int(bytes[index + 1]) | (Int(bytes[index + 2]) << 8)
            index += 3
        case 0x82:
            guard index + 4 < bytes.count else { return "" }
            length =
                Int(bytes[index + 1]) | (Int(bytes[index + 2]) << 8) | (Int(bytes[index + 3]) << 16)
                | (Int(bytes[index + 4]) << 24)
            index += 5
        default:
            length = Int(bytes[index])
            index += 1
        }
        guard length > 0, index + length <= bytes.count else { return "" }
        return String(decoding: bytes[index..<(index + length)], as: UTF8.self)
    }

    private static func firstRange(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return start + needle.count
        }
        return nil
    }
}

enum MessagesFailure: Error, CustomStringConvertible {
    case cannotOpen(Int32, String?)
    case schema(String)

    var description: String {
        switch self {
        case .cannotOpen(let code, let message):
            code == SQLITE_AUTH || code == SQLITE_CANTOPEN
                ? "Information Bridge may not read Messages - give it Full Disk Access (System Settings → Privacy & Security → Full Disk Access), then turn Messages off and on"
                : "could not open Messages' database (\(code)): \(message ?? "")"
        case .schema(let message):
            "Messages' database is not the shape the Bridge knows - a macOS update may have changed it: \(message)"
        }
    }
}
