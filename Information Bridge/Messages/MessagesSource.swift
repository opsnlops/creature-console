import Foundation
import WorldCore
import os

/// Step 6 of the plan: what people tell April by text. Every minute, whatever is new in
/// Messages' database is read; only texts from people April has mapped (and, if she lists
/// them, a carrier's numbers) are looked at, and only by the on-device model, which says what
/// kind of thing each is - on the way, a request, news, a delivery - in a few words. The world
/// gets those words on the person, for as long as they matter; the text itself is never
/// written down and never leaves the Mac. April's own texts are skipped. Group chats are off
/// unless she says otherwise.
actor MessagesSource {
    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void
    /// Everything after a row; with no row yet, everything since a date.
    typealias Fetch = @Sendable (_ afterRowID: Int64?, _ since: Date) async throws -> [TextMessage]
    /// The message, the sender's name, and the lines of the thread before it.
    typealias Distill = @Sendable (TextMessage, String, [String]) async -> MessageReading?
    typealias Resolver = @Sendable () async -> PersonResolver
    /// Why the model cannot read right now, or nil when it can.
    typealias ModelCheck = @Sendable () -> String?

    static let sourceName = "messages"
    /// Every step, as it goes, for Xcode's console: what was read, what it became. The words
    /// of a text are `.private` - shown while a debugger is attached, redacted in the system
    /// log, never in a log archive.
    static let log = Logger(subsystem: "io.opsnlops.Information-Bridge", category: "messages")
    static let interval: Duration = .seconds(60)
    /// A first run reads only the last day unless April says otherwise; nothing said before
    /// the Bridge was listening is a fact about now, and what has run out is never cast.
    private let firstRunLookback: TimeInterval

    private let house: EntityID
    private let zone: TimeZone
    private let fetch: Fetch
    private let distill: Distill
    private let modelCheck: ModelCheck
    private let resolver: Resolver
    private let cast: Cast
    private let ledger: FactLedger
    private let stateFile: URL
    private let logFile: URL
    private var readGroupChats: Bool
    /// Handles read even when unmapped: the carriers' short codes.
    private var extraHandles: Set<String>
    private var state = State()
    /// The last few lines of each thread, both sides, kept only in memory - the model reads a
    /// reply in the light of what came before, and nothing of it is ever written down.
    private var threads: [String: [String]] = [:]
    /// A read in progress; another asked for meanwhile waits its turn rather than running
    /// alongside and reading the same rows twice.
    private var polling = false
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?

    private struct State: Codable {
        var lastRowID: Int64?
        var told: [MessageTold] = []
    }

    init(
        directory: URL, house: EntityID, zone: TimeZone = .current, readGroupChats: Bool,
        extraHandles: [String], lookbackDays: Int = 1,
        fetch: @escaping Fetch,
        distill: @escaping Distill = { await MessageDistiller().read($0, sender: $1, context: $2) },
        modelCheck: @escaping ModelCheck = { MessageDistiller.unavailableReason() },
        resolver: @escaping Resolver, cast: @escaping Cast
    ) {
        self.modelCheck = modelCheck
        self.house = house
        self.zone = zone
        self.readGroupChats = readGroupChats
        firstRunLookback = TimeInterval(max(1, lookbackDays)) * 86_400
        self.extraHandles = Set(extraHandles.map(PersonResolver.phoneKey).filter { !$0.isEmpty })
        self.fetch = fetch
        self.distill = distill
        self.resolver = resolver
        self.cast = cast
        ledger = FactLedger(source: Self.sourceName, directory: directory)
        stateFile = directory.appending(path: "messages-state.json")
        logFile = directory.appending(path: "message-readings.log")
        if let data = try? Data(contentsOf: stateFile),
            let saved = try? WorldJSON.makeDecoder().decode(State.self, from: data)
        {
            state = saved
        }
    }

    /// What the texts have told the Bridge lately, newest first - for the window.
    var told: [MessageTold] { state.told.sorted { $0.said > $1.said } }

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

    /// Forgets the checkpoint and everything told, and reads the look-back window again, as a
    /// first read would; whatever is not told again is taken back from the world.
    func startOver() async {
        state.lastRowID = nil
        state.told = []
        threads = [:]
        Self.log.notice("Messages: starting over")
        await poll()
    }

    func poll(now: Date = Date()) async {
        guard !polling else { return }
        polling = true
        defer { polling = false }
        if let reason = modelCheck() {
            Self.log.error("Messages: not reading - \(reason, privacy: .public)")
            status = SourceStatus(state: .degraded(reason), lastRunAt: now)
            publish()
            return
        }
        do {
            if let last = state.lastRowID {
                Self.log.notice("Messages: reading rows after \(last)")
            } else {
                Self.log.notice(
                    "Messages: first read, the last \(Int(self.firstRunLookback / 86_400)) day(s) only"
                )
            }
            let messages = try await fetch(
                state.lastRowID, now.addingTimeInterval(-firstRunLookback))
            Self.log.notice("Messages: \(messages.count) new row\(messages.count == 1 ? "" : "s")")
            let resolver = await resolver()
            var read = 0
            for message in messages {
                state.lastRowID = max(state.lastRowID ?? 0, message.rowID)
                // The first run skips the past: a text from last week is not news tonight.
                guard message.date > now.addingTimeInterval(-firstRunLookback),
                    !message.text.isEmpty, readGroupChats || !message.isGroupChat
                else {
                    Self.log.debug(
                        "Messages: row \(message.rowID) skipped (\(message.isGroupChat ? "group chat" : message.text.isEmpty ? "no words" : "too old", privacy: .public))"
                    )
                    continue
                }
                let person = resolver.person(handle: message.handle)
                let carrier = extraHandles.contains(PersonResolver.phoneKey(message.handle))
                let sender = message.isFromMe ? "April" : Self.name(of: person, carrier: carrier)
                // The thread so far, for the model: April's own lines included, so a reply
                // reads as a reply. Only threads with someone April knows are kept at all.
                let context = threads[message.chatIdentifier] ?? []
                if person != nil || carrier {
                    threads[message.chatIdentifier] =
                        Array(
                            (context + ["\(sender): \(message.text)"]).suffix(
                                MessageDistiller.contextLines))
                }
                guard !message.isFromMe else {
                    Self.log.debug("Messages: row \(message.rowID) skipped (from April)")
                    continue
                }
                guard person != nil || carrier else {
                    Self.log.notice(
                        "Messages: row \(message.rowID) from \(message.handle, privacy: .private) - nobody April has mapped, skipped unread"
                    )
                    continue
                }
                read += 1
                Self.log.notice(
                    "Messages: row \(message.rowID) from \(person?.rawValue ?? "a carrier", privacy: .public) (\(message.handle, privacy: .private)): \"\(message.text, privacy: .private)\" - asking the model"
                )
                guard let reading = await distill(message, sender, context),
                    reading.kind != .nothing, !reading.what.isEmpty
                else {
                    Self.log.notice("Messages: row \(message.rowID) - nothing to tell")
                    log(message, became: "nothing", now: now)
                    continue
                }
                Self.log.notice(
                    "Messages: row \(message.rowID) - \(reading.kind.rawValue, privacy: .public): \"\(reading.what, privacy: .public)\" \(reading.when, privacy: .public)"
                )
                let kind: MessageTold.Kind
                switch reading.kind {
                case .visit: kind = .visit
                case .request: kind = .request
                case .news: kind = .news
                case .delivery: kind = .delivery
                case .nothing: continue
                }
                // A carrier's number only ever says a package came; a friend's never does.
                guard (kind == .delivery) == (person == nil) else {
                    log(message, became: "\(kind.rawValue), ignored", now: now)
                    continue
                }
                let told = MessageTold(
                    rowID: message.rowID, person: person ?? house, kind: kind,
                    what: reading.what, when: reading.when, said: message.date,
                    until: MessageFacts.until(
                        kind, when: reading.when, said: message.date, zone: zone))
                state.told.append(told)
                log(message, became: "\(kind.rawValue): \(told.what)", now: now)
            }
            // What has run out is let go quietly: the world expired it already.
            let expired = state.told.filter { $0.until <= now }
            if !expired.isEmpty {
                await ledger.forget(Set(expired.map(\.item)))
                state.told.removeAll { $0.until <= now }
            }
            var wanted: [String: FactLedger.Wanted] = [:]
            for told in state.told {
                wanted[told.item] = MessageFacts.wanted(told, house: house, now: now, zone: zone)
            }
            let cast = await ledger.reconcile(wanted, now: now, cast: cast)
            if state.lastRowID == nil { state.lastRowID = 0 }
            save()
            Self.log.notice(
                "Messages: done - \(read) read, \(self.state.told.count) in force, \(cast) fact\(cast == 1 ? "" : "s") cast"
            )
            let note =
                messages.isEmpty
                ? "nothing new" : "\(messages.count) new, \(read) from people April knows"
            status = SourceStatus(
                state: .on, lastRunAt: now,
                note: cast > 0 ? "\(note); \(cast) fact\(cast == 1 ? "" : "s") cast" : note)
        } catch {
            Self.log.error("Messages: \("\(error)", privacy: .public)")
            status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now)
        }
        publish()
    }

    /// "Jesse", from `person:jesse`; "the carrier" for a listed number.
    private static func name(of person: EntityID?, carrier: Bool) -> String {
        guard let person else { return carrier ? "the carrier" : "someone" }
        return person.rawValue.split(separator: ":").last.map { String($0).capitalized }
            ?? "someone"
    }

    /// One line per text read, on this Mac: when, from which handle, what it became. Never
    /// the words.
    private func log(_ message: TextMessage, became: String, now: Date) {
        let line = "\(WorldJSON.timestamp(message.date)) \(message.handle) → \(became)\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: logFile)
        }
    }

    private func save() {
        try? WorldJSON.makeEncoder().encode(state).write(to: stateFile, options: .atomic)
    }

    private func publish() {
        for observer in observers.values { observer.yield(status) }
    }
}
