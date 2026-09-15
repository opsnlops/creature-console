import Foundation
import MailKit

/// Every incoming message, handed to the Bridge: sender, subject, date, and the plain text of
/// the body, written as one small JSON file into the app group's drop folder. Mail is told to
/// do nothing to the message. The Bridge reads the folder every minute, classifies, distills,
/// and deletes the file. The raw message never leaves Mail's own store.
final class MailHandoff: NSObject, MEMessageActionHandler {
    static let appGroup = "group.io.opsnlops.information-bridge"

    func decideAction(
        for message: MEMessage, completionHandler: @escaping (MEMessageActionDecision?) -> Void
    ) {
        defer { completionHandler(.invokeAgainWithBody) }
        guard let raw = message.rawData else { return }
        let text = Self.plainText(of: raw)
        let handed = HandedMessage(
            identifier: "mail:" + Self.stableID(of: message),
            from: message.fromAddress.rawString,
            subject: message.subject,
            date: message.__dateSent ?? message.__dateReceived ?? Date(),
            text: text)
        guard
            let folder = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroup)?.appending(path: "mail-drop")
        else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let name = "\(stamp)-\(UUID().uuidString).json"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(handed).write(to: folder.appending(path: name), options: .atomic)
    }

    /// The Message-ID header when there is one, else a hash of sender, subject, and date.
    private static func stableID(of message: MEMessage) -> String {
        if let id = message.headers?["message-id"]?.first, !id.isEmpty {
            return id.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        }
        var seed = message.fromAddress.rawString
        seed += "|" + message.subject
        seed += "|\(message.__dateSent?.timeIntervalSince1970 ?? 0)"
        return String(seed.hashValue, radix: 16)
    }

    /// The body as text: the text/plain part when the message has one, else the HTML with its
    /// tags stripped. Good enough for numbers, statuses, and the on-device model.
    static func plainText(of raw: Data) -> String {
        let whole = String(decoding: raw, as: UTF8.self)
        // Headers end at the first blank line.
        let body =
            whole.range(of: "\r\n\r\n").map { String(whole[$0.upperBound...]) }
            ?? whole.range(of: "\n\n").map { String(whole[$0.upperBound...]) } ?? whole
        var text = body
        if let plain = part(of: body, contentType: "text/plain") {
            text = plain
        } else if let html = part(of: body, contentType: "text/html") {
            text = html
        }
        if text.contains("<") {
            text = text.replacingOccurrences(
                of: "<style[^>]*>[\\s\\S]*?</style>|<script[^>]*>[\\s\\S]*?</script>", with: " ",
                options: .regularExpression)
            text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
        }
        if text.contains("=\r\n") || text.contains("=3D") {
            text = text.replacingOccurrences(of: "=\r\n", with: "")
                .replacingOccurrences(of: "=\n", with: "")
                .replacingOccurrences(of: "=3D", with: "=")
                .replacingOccurrences(of: "=20", with: " ")
        }
        return text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first MIME part of `contentType` in a multipart body, decoded loosely.
    private static func part(of body: String, contentType: String) -> String? {
        guard let header = body.range(of: "Content-Type: \(contentType)", options: .caseInsensitive)
        else { return nil }
        let after = body[header.upperBound...]
        guard let start = after.range(of: "\r\n\r\n") ?? after.range(of: "\n\n") else { return nil }
        let content = after[start.upperBound...]
        let end = content.range(of: "\n--").map { $0.lowerBound } ?? content.endIndex
        let chunk = String(content[..<end])
        if after[..<start.lowerBound].range(of: "base64", options: .caseInsensitive) != nil,
            let data = Data(base64Encoded: chunk.filter { !$0.isWhitespace })
        {
            return String(decoding: data, as: UTF8.self)
        }
        return chunk
    }
}

/// The same shape the Bridge decodes as `MailMessage`; kept here as its own type so the
/// extension links nothing but MailKit and Foundation.
private struct HandedMessage: Encodable {
    var identifier: String
    var from: String
    var subject: String
    var date: Date
    var text: String
}
