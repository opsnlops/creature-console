import Foundation

/// One `event:`/`id:`/`data:` frame from a `text/event-stream` body.
public struct ServerSentEvent: Equatable, Sendable {
    public var event: String
    public var id: String?
    public var data: String

    public init(event: String, id: String? = nil, data: String) {
        self.event = event
        self.id = id
        self.data = data
    }
}

/// Incremental parser for `\n\n`-delimited SSE frames. Comment lines (keep-alives) are dropped.
public struct ServerSentEventParser: Sendable {
    private var pending = ""

    public init() {}

    /// Feeds raw bytes and returns every complete frame they finished.
    public mutating func feed(_ chunk: String) -> [ServerSentEvent] {
        pending += chunk
        var frames: [ServerSentEvent] = []
        while let range = pending.range(of: "\n\n") {
            let raw = String(pending[..<range.lowerBound])
            pending = String(pending[range.upperBound...])
            if let frame = Self.parse(raw) {
                frames.append(frame)
            }
        }
        return frames
    }

    private static func parse(_ raw: String) -> ServerSentEvent? {
        var event = "message"
        var id: String?
        var data: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = line[..<colon]
            var value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
            switch field {
            case "event": event = String(value)
            case "id": id = String(value)
            case "data": data.append(String(value))
            default: break
            }
        }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(event: event, id: id, data: data.joined(separator: "\n"))
    }
}
