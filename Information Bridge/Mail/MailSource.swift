import Foundation
import WorldCore

/// Step 5 of the plan: April's mail, straight from her IMAP accounts - her own server, iCloud
/// - with no Mail.app between. The first read of a mailbox goes back 120 days; every read after
/// asks only for what is newer, every five minutes. Each message from the carriers and merchants
/// April lists is classified cheaply, read for its numbers, read again by the on-device model
/// for the rest, folded into the order book, and forgotten. The world holds orders; it never
/// holds mail.
actor MailSource {
    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void
    typealias Distill = @Sendable (MailMessage) async -> CommerceReading?
    /// Everything new from the accounts; the intake remembers where it was.
    typealias Fetch =
        @Sendable (_ progress: @Sendable (String) async -> Void) async throws
        -> [MailMessage]

    static let sourceName = "mail"
    static let interval: Duration = .seconds(300)
    static let backfillDays = 120
    /// Bumped when the readers change: the mail is read again and the orders rebuilt.
    static let readingVersion = 5

    private let classifier: MailClassifier
    private let distill: Distill
    private let fetch: Fetch
    private let cast: Cast
    private let ledger: FactLedger
    private let bookFile: URL
    private let seenFile: URL
    private var book = OrderBook()
    private var seen: Set<String> = []
    /// What the last read made of its mail, by kind - for the window, and a subjects-only log
    /// on this Mac (`mail-readings.log`: date, kind, sender, subject; never a body).
    private var tally: [MailKind: Int] = [:]
    private let logFile: URL
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?

    init(
        directory: URL, classifier: MailClassifier, fetch: @escaping Fetch,
        distill: @escaping Distill = { await MailDistiller().read($0) }, cast: @escaping Cast
    ) {
        self.classifier = classifier
        self.distill = distill
        self.fetch = fetch
        self.cast = cast
        ledger = FactLedger(source: Self.sourceName, directory: directory)
        bookFile = directory.appending(path: "orders.json")
        seenFile = directory.appending(path: "mail-seen.json")
        logFile = directory.appending(path: "mail-readings.log")
        let decoder = WorldJSON.makeDecoder()
        if let data = try? Data(contentsOf: seenFile),
            let saved = try? decoder.decode(Seen.self, from: data),
            saved.readingVersion == Self.readingVersion
        {
            seen = saved.identifiers
            if let data = try? Data(contentsOf: bookFile),
                let book = try? decoder.decode(OrderBook.self, from: data)
            {
                self.book = book
            }
        }
    }

    var orders: [Order] { Array(book.orders.values).sorted { $0.lastMail > $1.lastMail } }

    func start() {
        guard worker == nil else { return }
        worker = Task {
            while !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        status.state = .off
        publish()
    }

    func updates() -> AsyncStream<SourceStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { _ in Task { await self.forget(id) } }
        }
    }

    private func forget(_ id: UUID) { observers[id] = nil }

    /// Asks the accounts for what is new, folds it in, and reconciles the orders with the world.
    func poll(now: Date = Date()) async {
        status = SourceStatus(state: .on, lastRunAt: status.lastRunAt, note: "reading mail…")
        publish()
        do {
            let messages = try await fetch { [weak self] line in
                await self?.report(line)
            }
            await take(messages, now: now)
        } catch {
            status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now)
            publish()
        }
    }

    private func report(_ line: String) {
        status.note = line
        publish()
    }

    /// One message, wherever it came from: classified, read, distilled, folded in, forgotten.
    func take(_ message: MailMessage) async {
        guard !seen.contains(message.identifier) else { return }
        seen.insert(message.identifier)
        let kind = classifier.classify(message)
        tally[kind, default: 0] += 1
        var line =
            "\(WorldJSON.timestamp(message.date)) \(kind.rawValue) <\(message.from)> \(message.subject)"
        defer { log(line) }
        guard kind == .order || kind == .shipping else { return }
        var reading = MailReader.read(message, kind: kind)
        reading = reading.filled(with: await distill(message))
        let order = book.apply(reading, at: message.date)
        line += " → \(order?.entityID.rawValue ?? "no order: needs an order or tracking number")"
    }

    private func log(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFile)
        }
    }

    /// Many messages at once - the backfill - then one reconciliation.
    func take(_ messages: [MailMessage], now: Date = Date()) async {
        tally = [:]
        var taken = 0
        for message in messages.sorted(by: { $0.date < $1.date }) {
            await take(message)
            taken += 1
            // A first read is hundreds of messages and the model takes a moment with each:
            // the world hears about the orders as they come, not at the end.
            if taken % 25 == 0 {
                await reconcile(now: now, note: "read \(taken) of \(messages.count)…")
            }
        }
        let kinds = tally.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value) \($0.key.rawValue)" }.joined(separator: ", ")
        await reconcile(
            now: now,
            note:
                "read \(messages.count) from the last 120 days (\(kinds.isEmpty ? "none new" : kinds))"
        )
    }

    private struct Seen: Codable {
        var readingVersion: Int
        var identifiers: Set<String>
    }

    private func reconcile(now: Date, note: String?) async {
        let encoder = WorldJSON.makeEncoder()
        try? encoder.encode(book).write(to: bookFile, options: .atomic)
        try? encoder.encode(Seen(readingVersion: Self.readingVersion, identifiers: seen))
            .write(to: seenFile, options: .atomic)
        let cast = await ledger.reconcile(book.wanted, now: now, cast: cast)
        var line = note ?? "\(book.orders.count) orders known"
        if cast > 0 { line += " · \(cast) fact\(cast == 1 ? "" : "s") changed" }
        if let why = MailDistiller.unavailableReason() {
            line += " · \(why)"
        }
        status = SourceStatus(state: .on, lastRunAt: now, note: line)
        publish()
    }

    private func publish() {
        for observer in observers.values { observer.yield(status) }
    }
}
