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
    typealias DistillAppointment = @Sendable (MailMessage) async -> AppointmentReading?
    /// The street lines of April's own address, for telling a visit to the house from one
    /// April makes; empty when the address book is off.
    typealias HomeStreets = @Sendable () async -> [String]
    /// Who a sender is in the address book - the business on their card, else their name -
    /// or nil for a stranger.
    typealias SenderName = @Sendable (_ from: String) async -> String?
    /// Everything new from the accounts, and a `commit` to call once they are taken - only
    /// then does the intake remember where it was.
    typealias Fetch =
        @Sendable (_ progress: @Sendable (String) async -> Void) async throws
        -> (messages: [MailMessage], commit: @Sendable () async -> Void)

    static let sourceName = "mail"
    static let interval: Duration = .seconds(300)
    static let backfillDays = 120
    /// Bumped when the readers change: the mail is read again and the orders rebuilt.
    static let readingVersion = 12

    private let classifier: MailClassifier
    private let house: EntityID
    private let zone: TimeZone
    private let distill: Distill
    private let distillAppointment: DistillAppointment
    private let homeStreets: HomeStreets
    private let senderName: SenderName
    private let fetch: Fetch
    private let cast: Cast
    private let ledger: FactLedger
    private let bookFile: URL
    private let seenFile: URL
    private var book = OrderBook()
    private var appointments = AppointmentBook()
    private let appointmentsFile: URL
    private var seen: Set<String> = []
    /// What the last read made of its mail, by kind - for the window, and a subjects-only log
    /// on this Mac (`mail-readings.log`: date, kind, sender, subject; never a body).
    private var tally: [MailKind: Int] = [:]
    private let logFile: URL
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?
    /// A read in progress; a nudge meanwhile (the server says mail came) is remembered and
    /// honoured straight after, never run alongside.
    private var polling = false
    private var pollAgain = false

    init(
        directory: URL, classifier: MailClassifier,
        house: EntityID = EntityID(rawValue: "house:aprils-nest")!, zone: TimeZone = .current,
        homeStreets: @escaping HomeStreets = { [] },
        senderName: @escaping SenderName = { _ in nil },
        fetch: @escaping Fetch,
        distill: @escaping Distill = { await MailDistiller().read($0) },
        distillAppointment: @escaping DistillAppointment = {
            await AppointmentDistiller().read($0)
        },
        cast: @escaping Cast
    ) {
        self.classifier = classifier
        self.house = house
        self.zone = zone
        self.distillAppointment = distillAppointment
        self.homeStreets = homeStreets
        self.senderName = senderName
        appointmentsFile = directory.appending(path: "appointments.json")
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
            if let data = try? Data(contentsOf: appointmentsFile),
                let saved = try? decoder.decode(AppointmentBook.self, from: data)
            {
                appointments = saved
            }
        }
    }

    var orders: [Order] { Array(book.orders.values).sorted { $0.lastMail > $1.lastMail } }
    var upcomingAppointments: [Appointment] {
        Array(appointments.appointments.values).sorted { $0.day < $1.day }
    }

    func start() {
        guard worker == nil else { return }
        worker = Task {
            while !Task.isCancelled {
                await self.poll()
                try? await Pace.sleep(for: Self.interval)
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
        guard !polling else {
            pollAgain = true
            return
        }
        polling = true
        defer { polling = false }
        repeat {
            pollAgain = false
            status = SourceStatus(state: .on, lastRunAt: status.lastRunAt, note: "reading mail…")
            publish()
            do {
                let (messages, commit) = try await fetch { [weak self] line in
                    await self?.report(line)
                }
                await take(messages, now: now)
                await commit()
            } catch {
                status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now)
                publish()
            }
        } while pollAgain
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
        if kind == .appointment {
            guard var reading = await distillAppointment(message) else {
                line += " → no reading"
                return
            }
            // A person's mail names no business: the sender is who is coming - the business
            // on their card, else their name.
            if reading.business.isEmpty {
                reading.business =
                    await senderName(message.from) ?? MailReader.displayName(of: message.from)
            }
            let atHome = AppointmentFacts.isAtHome(message, homeStreets: await homeStreets())
            let appointment = appointments.apply(
                reading, mailedOn: message.date, zone: zone, atHome: atHome)
            line +=
                " → \(appointment.map { "\($0.entityID.rawValue)\($0.atHome ? " at home" : "")" } ?? "no appointment: needs a business and a day")"
            return
        }
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
                // Part-way through: say what is known so far, take nothing back yet.
                await reconcile(
                    now: now, keepingMissing: true, note: "read \(taken) of \(messages.count)…")
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

    private func reconcile(now: Date, keepingMissing: Bool = false, note: String?) async {
        let encoder = WorldJSON.makeEncoder()
        try? encoder.encode(book).write(to: bookFile, options: .atomic)
        appointments.forgetPast(now: now, zone: zone)
        try? encoder.encode(appointments).write(to: appointmentsFile, options: .atomic)
        try? encoder.encode(Seen(readingVersion: Self.readingVersion, identifiers: seen))
            .write(to: seenFile, options: .atomic)
        let wanted = book.wanted.merging(appointments.wanted(zone: zone, house: house)) { _, new in
            new
        }
        let cast = await ledger.reconcile(
            wanted, now: now, keepingMissing: keepingMissing, cast: cast)
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
