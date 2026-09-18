import EventKit
import Foundation
import WorldCore

/// Step 4 of the plan: April's calendars. Everything ahead and the last 90 days, from the
/// calendars she allows, as `event:*` entities linked to the people she has mapped. Re-read
/// hourly and whenever the calendar store says it changed; a cancelled event is taken back.
actor CalendarSource {
    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void
    typealias Read =
        @Sendable (_ from: Date, _ to: Date, _ calendars: Set<String>?) async throws
        -> [CalendarItem]
    typealias Resolver = @Sendable () async -> PersonResolver

    static let sourceName = "calendar"
    static let interval: Duration = .seconds(3_600)
    static let daysBack: TimeInterval = 90
    static let daysAhead: TimeInterval = 365

    private let read: Read
    private let resolver: Resolver
    private let cast: Cast
    private let ledger: FactLedger
    /// The world read back, to take back events it holds that the calendars no longer have,
    /// whatever this Mac's ledger remembers. Nil in tests without a world.
    private let mirror: WorldMirror?
    private let zone: TimeZone
    /// Calendar titles April allows; nil means all of them.
    private var allowed: Set<String>?
    private(set) var items: [CalendarItem] = []
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?
    /// EventKit says the store changed - an event added, moved, or deleted, on any device
    /// once iCloud brings it here - and the calendars are read again at once. April deleted
    /// tomorrow's bloodwork and Beaky still announced it: the hourly poll was the only reader.
    private let store = EKEventStore()
    private var changeObserver: (any NSObjectProtocol)?
    private var rereadSoon: Task<Void, Never>?

    init(
        directory: URL, zone: TimeZone, allowed: Set<String>?,
        read: @escaping Read = CalendarSource.readFromEventKit, resolver: @escaping Resolver,
        mirror: WorldMirror? = nil, cast: @escaping Cast
    ) {
        self.read = read
        self.resolver = resolver
        self.cast = cast
        self.mirror = mirror
        self.zone = zone
        self.allowed = allowed
        ledger = FactLedger(source: Self.sourceName, directory: directory)
    }

    func start() {
        guard worker == nil else { return }
        worker = Task {
            while !Task.isCancelled {
                await self.poll()
                try? await Pace.sleep(for: Self.interval)
            }
        }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: nil
        ) { _ in
            Task { await self.storeChanged() }
        }
    }

    /// A change lands as a burst of notifications; one re-read a moment after the last.
    private func storeChanged() {
        rereadSoon?.cancel()
        rereadSoon = Task {
            try? await Pace.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self.poll()
        }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        rereadSoon?.cancel()
        rereadSoon = nil
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
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

    func setAllowed(_ calendars: Set<String>?) async {
        allowed = calendars
        await poll()
    }

    /// Reads the calendars and casts what changed.
    func poll(now: Date = Date()) async {
        do {
            items = try await read(
                now.addingTimeInterval(-Self.daysBack * 86_400),
                now.addingTimeInterval(Self.daysAhead * 86_400), allowed)
            let resolver = await resolver()
            var wanted: [String: FactLedger.Wanted] = [:]
            for item in items {
                wanted[item.identifier] = CalendarFacts.facts(
                    from: item, resolver: resolver, zone: zone)
            }
            var cast = await ledger.reconcile(wanted, now: now, cast: cast)
            // And the world's side of it: an event the world still holds inside the window
            // that the calendars no longer have is taken back, ledger or no ledger - but only
            // by a source that can see. A read that found nothing at all (no calendar
            // allowed by that name here, an account not on this Mac) says nothing about the
            // world; on 2026-09-17 it said everything was a ghost and took the calendar down.
            if let mirror, !items.isEmpty {
                let from = now.addingTimeInterval(-Self.daysBack * 86_400)
                let to = now.addingTimeInterval(Self.daysAhead * 86_400)
                let ghosts = try await mirror.ghosts(
                    prefix: "calendar.", wanted: Set(wanted.values.map(\.entityID))
                ) { _, facts in
                    guard
                        case .string(let raw)? = facts.first(where: {
                            $0.predicate == "calendar.starts_at"
                        })?.value, let starts = WorldJSON.date(from: raw)
                    else { return false }
                    return starts >= from && starts <= to
                }
                cast += await ledger.retractGhosts(ghosts, now: now, cast: self.cast)
            }
            let linked = wanted.values.filter { $0.facts["calendar.with"] != nil }.count
            status = SourceStatus(
                state: .on, lastRunAt: now,
                note: cast > 0
                    ? "\(cast) fact\(cast == 1 ? "" : "s") changed"
                    : "\(items.count) events, \(linked) with people April knows")
        } catch {
            status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now)
        }
        publish()
    }

    private func publish() {
        for observer in observers.values { observer.yield(status) }
    }

    /// The calendars EventKit knows, for the settings list.
    static func calendarTitles() async throws -> [String] {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw CalendarFailure.denied }
        return store.calendars(for: .event).map(\.title).sorted()
    }

    /// EventKit, for real, under its own permission.
    static func readFromEventKit(from: Date, to: Date, calendars: Set<String>?) async throws
        -> [CalendarItem]
    {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw CalendarFailure.denied }
        let all = store.calendars(for: .event)
        let chosen = all.filter { calendar in calendars?.contains(calendar.title) ?? true }
        guard !chosen.isEmpty else {
            throw CalendarFailure.noneAllowed(
                wanted: calendars.map { $0.sorted() } ?? [], here: all.map(\.title).sorted())
        }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: chosen)
        return store.events(matching: predicate).map { event in
            CalendarItem(
                identifier: event.calendarItemIdentifier + ":"
                    + WorldJSON.timestamp(event.startDate),
                calendar: event.calendar.title, title: event.title ?? "",
                location: event.location ?? "", notes: event.notes ?? "",
                starts: event.startDate, ends: event.endDate, isAllDay: event.isAllDay,
                attendees: (event.attendees ?? []).map { attendee in
                    CalendarItem.Attendee(
                        name: attendee.name ?? "",
                        email: attendee.url.scheme == "mailto" ? attendee.url.path : nil)
                })
        }
    }
}

enum CalendarFailure: Error, CustomStringConvertible {
    case denied
    /// The allowed calendars match none on this Mac: a settings list carried over from
    /// another Mac, or an account not signed in here. Said out loud, never read as "no events".
    case noneAllowed(wanted: [String], here: [String])
    var description: String {
        switch self {
        case .denied:
            "Information Bridge may not read Calendars (System Settings → Privacy & Security → Calendars)"
        case .noneAllowed(let wanted, let here):
            "none of the allowed calendars (\(wanted.joined(separator: ", "))) is on this Mac; here: \(here.joined(separator: ", "))"
        }
    }
}
