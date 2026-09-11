import Common
import Foundation
import WorldCore

public typealias WorldStreamFrames = AsyncThrowingStream<WorldStreamFrame, any Error>

/// Read-only typed client for Creature World's `/world/v1` API, for World Viewer.
///
/// Every list is bounded and paged; the live stream yields typed frames and resumes from a
/// sequence with `Last-Event-ID`. The client never writes to the world.
public struct WorldViewerClient: Sendable {
    public static let maximumPageSize = 500

    private let connection: CreatureServiceConnection
    private let loader: any HTTPDataLoading

    public init(
        connection: CreatureServiceConnection, loader: any HTTPDataLoading = URLSession.shared
    ) {
        self.connection = connection
        self.loader = loader
    }

    public func health() async throws -> WorldHealth {
        try await get(WorldHealth.self, pathComponents: ["health"])
    }

    public func events(after sequence: Int64, limit: Int = 100) async throws -> WorldEventPage {
        try await get(
            WorldEventPage.self,
            pathComponents: ["events"],
            queryItems: [
                URLQueryItem(name: "after_sequence", value: String(sequence)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    public func facts(
        subjectID: EntityID? = nil,
        after factID: FactID? = nil,
        limit: Int = 100
    ) async throws -> WorldFactPage {
        try await get(
            WorldFactPage.self,
            pathComponents: ["facts"],
            queryItems: [
                subjectID.map { URLQueryItem(name: "subject_id", value: $0.rawValue) },
                factID.map { URLQueryItem(name: "after_fact_id", value: $0.rawValue) },
                URLQueryItem(name: "limit", value: String(limit)),
            ].compactMap { $0 }
        )
    }

    public func timers(
        status: WorldTimerStatus? = nil,
        after timerID: TimerID? = nil,
        limit: Int = 100
    ) async throws -> WorldTimerPage {
        try await get(
            WorldTimerPage.self,
            pathComponents: ["timers"],
            queryItems: [
                status.map { URLQueryItem(name: "status", value: $0.rawValue) },
                timerID.map { URLQueryItem(name: "after_timer_id", value: $0.rawValue) },
                URLQueryItem(name: "limit", value: String(limit)),
            ].compactMap { $0 }
        )
    }

    public func conversationItems(
        in conversationID: ConversationID,
        after itemID: ConversationItemID? = nil,
        limit: Int = 100
    ) async throws -> ConversationItemPage {
        try await get(
            ConversationItemPage.self,
            pathComponents: ["conversations", conversationID.rawValue, "items"],
            queryItems: [
                itemID.map { URLQueryItem(name: "after_item_id", value: $0.rawValue) },
                URLQueryItem(name: "limit", value: String(limit)),
            ].compactMap { $0 }
        )
    }

    public func deliveries(
        in conversationID: ConversationID,
        after responseID: ResponseID? = nil,
        limit: Int = 100
    ) async throws -> CharacterDeliveryPage {
        try await get(
            CharacterDeliveryPage.self,
            pathComponents: ["conversations", conversationID.rawValue, "deliveries"],
            queryItems: [
                responseID.map { URLQueryItem(name: "after_response_id", value: $0.rawValue) },
                URLQueryItem(name: "limit", value: String(limit)),
            ].compactMap { $0 }
        )
    }

    /// Follows `/world/v1/stream`. With `resumeAfter` the world replays history from that
    /// sequence as `event` frames before live `delta`s; without it the first frame is a snapshot.
    public func eventStream(resumeAfter sequence: Int64?) throws -> WorldStreamFrames {
        var request = try request(pathComponents: ["stream"])
        request.httpMethod = "GET"
        if let sequence {
            request.setValue(String(sequence), forHTTPHeaderField: "Last-Event-ID")
        }
        request.timeoutInterval = 3_600
        let streamRequest = request

        #if os(macOS) || os(iOS)
            return WorldStreamFrames(bufferingPolicy: .bufferingOldest(256)) { continuation in
                let task = Task {
                    do {
                        let (bytes, response) = try await URLSession.shared.bytes(
                            for: streamRequest)
                        try Self.validate(response)
                        var parser = ServerSentEventFrameParser()
                        // Not `bytes.lines`: AsyncLineSequence drops the empty line that
                        // terminates an SSE frame, so a frame would never be delivered.
                        for try await line in bytes.sseLines {
                            for frame in parser.feed(line: line) {
                                if let typed = try Self.frame(from: frame) {
                                    continuation.yield(typed)
                                }
                            }
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        #else
            return WorldStreamFrames {
                $0.finish(throwing: WorldConversationClientError.streamingUnavailable)
            }
        #endif
    }

    /// Decodes one SSE frame into a typed stream frame; comments and unknown events are skipped.
    static func frame(from frame: ServerSentEventFrame) throws -> WorldStreamFrame? {
        let decoder = WorldJSON.makeDecoder()
        let data = Data(frame.data.utf8)
        switch frame.event {
        case "snapshot": return .snapshot(try decoder.decode(WorldSnapshot.self, from: data))
        case "event": return .event(try decoder.decode(WorldEventEnvelope.self, from: data))
        case "delta": return .delta(try decoder.decode(WorldDelta.self, from: data))
        case "resnapshot_required": return .resnapshotRequired
        default: return nil
        }
    }

    // MARK: - Transport

    private func get<Value: Decodable>(
        _ type: Value.Type,
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) async throws -> Value {
        var request = try request(pathComponents: pathComponents, queryItems: queryItems)
        request.httpMethod = "GET"
        let (data, response) = try await loader.data(for: request)
        try Self.validate(response)
        return try WorldJSON.makeDecoder().decode(type, from: data)
    }

    private func request(
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard
            var url = URL(
                string: connection.baseURLString(transport: .http, pathPrefix: "/world/v1"))
        else { throw WorldConversationClientError.invalidBaseURL }
        for component in pathComponents {
            url.append(path: component)
        }
        if !queryItems.isEmpty {
            url.append(queryItems: queryItems)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        connection.applyProxyHeaders(to: &request)
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw WorldConversationClientError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WorldConversationClientError.requestFailed(statusCode: http.statusCode)
        }
    }
}

extension AsyncSequence where Element == UInt8, Self: Sendable {
    /// Splits a byte stream into lines on `\n` (tolerating `\r\n`), **keeping empty lines**,
    /// because an empty line is what ends a `text/event-stream` frame.
    var sseLines: AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var buffer: [UInt8] = []
                    for try await byte in self {
                        if byte == UInt8(ascii: "\n") {
                            if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
                            continuation.yield(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(String(decoding: buffer, as: UTF8.self))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

/// One `event:`/`id:`/`data:` frame of a `text/event-stream` body.
public struct ServerSentEventFrame: Equatable, Sendable {
    public var event: String
    public var id: String?
    public var data: String
}

/// Line-by-line SSE parser: a blank line ends a frame; comment lines are ignored.
public struct ServerSentEventFrameParser: Sendable {
    private var event = "message"
    private var id: String?
    private var data: [String] = []

    public init() {}

    public mutating func feed(line: String) -> [ServerSentEventFrame] {
        if line.isEmpty {
            defer {
                event = "message"
                id = nil
                data = []
            }
            guard !data.isEmpty else { return [] }
            return [ServerSentEventFrame(event: event, id: id, data: data.joined(separator: "\n"))]
        }
        if line.hasPrefix(":") { return [] }
        guard let colon = line.firstIndex(of: ":") else { return [] }
        let field = line[..<colon]
        var value = line[line.index(after: colon)...]
        if value.hasPrefix(" ") { value = value.dropFirst() }
        switch field {
        case "event": event = String(value)
        case "id": id = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return []
    }
}
