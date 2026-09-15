import Foundation
import WorldCore

/// Step 5 of the plan: April's mail. Messages arrive two ways - the Mail extension drops each
/// incoming one it was handed into the shared folder, and a one-time backfill asks Mail itself
/// for the last 120 days from the carriers and merchants April lists. Each is classified
/// cheaply, read for its numbers, read again by the on-device model for the rest, folded into
/// the order book, and forgotten. The world holds orders; it never holds mail.
actor MailSource {
    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void
    typealias Distill = @Sendable (MailMessage) async -> CommerceReading?

    static let sourceName = "mail"
    static let appGroup = "group.io.opsnlops.information-bridge"
    static let interval: Duration = .seconds(60)

    private let classifier: MailClassifier
    private let distill: Distill
    private let cast: Cast
    private let ledger: FactLedger
    private let bookFile: URL
    private let seenFile: URL
    private let dropFolder: URL?
    private var book = OrderBook()
    private var seen: Set<String> = []
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?

    init(
        directory: URL, classifier: MailClassifier,
        dropFolder: URL? = MailSource.sharedDropFolder(),
        distill: @escaping Distill = { await MailDistiller().read($0) }, cast: @escaping Cast
    ) {
        self.classifier = classifier
        self.distill = distill
        self.cast = cast
        self.dropFolder = dropFolder
        ledger = FactLedger(source: Self.sourceName, directory: directory)
        bookFile = directory.appending(path: "orders.json")
        seenFile = directory.appending(path: "mail-seen.json")
        let decoder = WorldJSON.makeDecoder()
        if let data = try? Data(contentsOf: bookFile),
            let saved = try? decoder.decode(OrderBook.self, from: data)
        {
            book = saved
        }
        if let data = try? Data(contentsOf: seenFile),
            let saved = try? decoder.decode(Set<String>.self, from: data)
        {
            seen = saved
        }
    }

    /// Where the Mail extension leaves what it was handed: the app group's container.
    static func sharedDropFolder() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "mail-drop")
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

    /// Takes what the extension dropped, then reconciles the orders with the world.
    func poll(now: Date = Date()) async {
        var taken = 0
        if let dropFolder {
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: dropFolder, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                    let message = try? WorldJSON.makeDecoder().decode(MailMessage.self, from: data)
                {
                    await take(message)
                    taken += 1
                }
                try? FileManager.default.removeItem(at: file)
            }
        }
        await reconcile(
            now: now, note: taken > 0 ? "\(taken) new mail\(taken == 1 ? "" : "s")" : nil)
    }

    /// One message, wherever it came from: classified, read, distilled, folded in, forgotten.
    func take(_ message: MailMessage) async {
        guard !seen.contains(message.identifier) else { return }
        seen.insert(message.identifier)
        let kind = classifier.classify(message)
        guard kind == .order || kind == .shipping else { return }
        var reading = MailReader.read(message, kind: kind)
        reading = reading.filled(with: await distill(message))
        book.apply(reading, at: message.date)
    }

    /// Many messages at once - the backfill - then one reconciliation.
    func take(_ messages: [MailMessage], now: Date = Date()) async {
        for message in messages.sorted(by: { $0.date < $1.date }) {
            await take(message)
        }
        await reconcile(now: now, note: "read \(messages.count) from the last 120 days")
    }

    private func reconcile(now: Date, note: String?) async {
        let encoder = WorldJSON.makeEncoder()
        try? encoder.encode(book).write(to: bookFile, options: .atomic)
        try? encoder.encode(seen).write(to: seenFile, options: .atomic)
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
