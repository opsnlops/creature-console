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
    private let zone: TimeZone
    /// Calendar titles April allows; nil means all of them.
    private var allowed: Set<String>?
    private(set) var items: [CalendarItem] = []
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?

    init(
        directory: URL, zone: TimeZone, allowed: Set<String>?,
        read: @escaping Read = CalendarSource.readFromEventKit, resolver: @escaping Resolver,
        cast: @escaping Cast
    ) {
        self.read = read
        self.resolver = resolver
        self.cast = cast
        self.zone = zone
        self.allowed = allowed
        ledger = FactLedger(source: Self.sourceName, directory: directory)
    }

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
            let cast = await ledger.reconcile(wanted, now: now, cast: cast)
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
        let chosen = store.calendars(for: .event).filter { calendar in
            calendars?.contains(calendar.title) ?? true
        }
        guard !chosen.isEmpty else { return [] }
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
    var description: String {
        "Information Bridge may not read Calendars (System Settings → Privacy & Security → Calendars)"
    }
}
