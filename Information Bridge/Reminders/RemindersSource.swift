import EventKit
import Foundation
import WorldCore

/// April's reminders, from every list, as `reminder:*` entities: what she means to do, by
/// when, and whether she has. Everything not done, and what was done in the last two days.
/// Re-read hourly and the moment EventKit says the store changed; a reminder deleted, or done
/// long enough ago, is taken back.
actor RemindersSource {
    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void
    typealias Read = @Sendable (_ doneSince: Date) async throws -> [ReminderItem]

    static let sourceName = "reminders"
    static let interval: Duration = .seconds(3_600)

    private let read: Read
    private let cast: Cast
    private let ledger: FactLedger
    private let mirror: WorldMirror?
    private let zone: TimeZone
    private(set) var items: [ReminderItem] = []
    private(set) var status = SourceStatus(state: .on)
    private var observers: [UUID: AsyncStream<SourceStatus>.Continuation] = [:]
    private var worker: Task<Void, Never>?
    private let store = EKEventStore()
    private var changeObserver: (any NSObjectProtocol)?
    private var rereadSoon: Task<Void, Never>?

    init(
        directory: URL, zone: TimeZone, read: @escaping Read = RemindersSource.readFromEventKit,
        mirror: WorldMirror? = nil, cast: @escaping Cast
    ) {
        self.read = read
        self.cast = cast
        self.mirror = mirror
        self.zone = zone
        ledger = FactLedger(source: Self.sourceName, directory: directory)
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

    /// Reads the lists and casts what changed.
    func poll(now: Date = Date()) async {
        do {
            items = try await read(now.addingTimeInterval(-ReminderFacts.doneLingers))
            var wanted: [String: FactLedger.Wanted] = [:]
            for item in items {
                wanted[item.identifier] = ReminderFacts.facts(from: item, zone: zone)
            }
            var cast = await ledger.reconcile(wanted, now: now, cast: cast)
            // The world's ghosts, only from a source that saw something.
            if let mirror, !items.isEmpty {
                let ghosts = try await mirror.ghosts(
                    prefix: "reminder.", wanted: Set(wanted.values.map(\.entityID)))
                cast += await ledger.retractGhosts(ghosts, now: now, cast: self.cast)
            }
            let open = items.filter { !$0.isCompleted }.count
            let due = items.filter { !$0.isCompleted && ($0.due.map { $0 <= now } ?? false) }.count
            status = SourceStatus(
                state: .on, lastRunAt: now,
                note: cast > 0
                    ? "\(cast) fact\(cast == 1 ? "" : "s") changed"
                    : "\(open) to do, \(due) due or overdue")
        } catch {
            status = SourceStatus(state: .degraded("\(error)"), lastRunAt: now)
        }
        publish()
    }

    private func publish() {
        for observer in observers.values { observer.yield(status) }
    }

    /// EventKit, for real, under its own permission: everything not done, and what was done
    /// since `doneSince`.
    static func readFromEventKit(doneSince: Date) async throws -> [ReminderItem] {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else {
            throw RemindersFailure.denied
        }
        // EventKit's objects are not Sendable: they are turned into plain values where the
        // fetch hands them over, and only the values cross.
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: nil)) { found in
                let items = (found ?? []).compactMap { reminder -> ReminderItem? in
                    if reminder.isCompleted, (reminder.completionDate ?? .distantPast) < doneSince {
                        return nil
                    }
                    let components = reminder.dueDateComponents
                    let due = components.flatMap { Calendar.current.date(from: $0) }
                    return ReminderItem(
                        identifier: reminder.calendarItemIdentifier,
                        list: reminder.calendar.title, title: reminder.title ?? "",
                        notes: reminder.notes ?? "", due: due,
                        dueHasTime: components?.hour != nil, priority: reminder.priority,
                        isCompleted: reminder.isCompleted, completedAt: reminder.completionDate)
                }
                continuation.resume(returning: items)
            }
        }
    }
}

enum RemindersFailure: Error, CustomStringConvertible {
    case denied
    var description: String {
        "Information Bridge may not read Reminders (System Settings → Privacy & Security → Reminders)"
    }
}
