import CreatureAppSupport
import Foundation
import Observation
import WorldCore

/// The sources the Bridge will read, in the order the plan builds them. All off until their
/// step ships; the window shows them so April can see what is coming and what is on.
enum BridgeSource: String, CaseIterable, Identifiable, Sendable {
    case weather, addressBook, calendar, mail, messages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: "Weather"
        case .addressBook: "Address Book"
        case .calendar: "Calendar"
        case .mail: "Mail"
        case .messages: "Messages"
        }
    }

    var symbol: String {
        switch self {
        case .weather: "cloud.sun"
        case .addressBook: "person.crop.rectangle.stack"
        case .calendar: "calendar"
        case .mail: "envelope"
        case .messages: "message"
        }
    }

    /// The plan's step that brings the source to life.
    var step: Int {
        switch self {
        case .weather: 2
        case .addressBook: 3
        case .calendar: 4
        case .mail: 5
        case .messages: 6
        }
    }
}

/// What the window and the menu bar show: the world, the outbox, the sources.
@MainActor
@Observable
final class BridgeStore {
    private(set) var health: WorldHealth?
    private(set) var healthError: String?
    private(set) var outbox = Outbox.Status()
    private(set) var worldURI = ""
    var lastError: ErrorAlert?

    static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    private let connection: BridgeConnection
    @ObservationIgnored private var box: Outbox?
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    init(connection: BridgeConnection = .shared) {
        self.connection = connection
    }

    var isConnected: Bool { health?.status == "ok" }

    var menuBarSymbol: String {
        if outbox.pending > 0 { return "tray.and.arrow.up" }
        return isConnected
            ? "point.3.connected.trianglepath.dotted"
            : "point.3.filled.connected.trianglepath.dotted"
    }

    /// Starts (or restarts, after a settings change) delivering and watching.
    func start() {
        stop()
        worldURI = connection.worldURI
        do {
            let box = try Outbox(directory: Self.supportDirectory())
            self.box = box
            let client = try connection.client()
            Task { await box.start { event in try await client.cast(event) } }
            statusTask = Task { [weak self] in
                for await status in await box.updates() {
                    guard let self else { return }
                    self.outbox = status
                }
            }
        } catch {
            lastError = ErrorAlert(title: "The Outbox Could Not Open", error: error)
        }
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshHealth()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.heartbeat()
                try? await Task.sleep(for: .seconds(1_800))
            }
        }
    }

    func stop() {
        healthTask?.cancel()
        heartbeatTask?.cancel()
        statusTask?.cancel()
        if let box {
            Task { await box.stop() }
        }
        box = nil
    }

    func refreshHealth() async {
        do {
            health = try await connection.client().health()
            healthError = nil
        } catch {
            health = nil
            healthError = "\(error)"
        }
    }

    /// The Bridge tells the world it is here, as a fact that expires if it stops.
    func heartbeat() async {
        await enqueue { try BridgeFacts.online(version: Self.version, host: Self.host) }
    }

    /// "Cast a test fact": a `bridge.hello` on the house, valid a minute.
    func castTestFact() async {
        await enqueue {
            try BridgeFacts.hello(
                house: connection.houseID, version: Self.version, host: Self.host)
        }
    }

    private func enqueue(_ make: () throws -> WorldEventEnvelope) async {
        guard let box else { return }
        do {
            try await box.enqueue(try make())
        } catch {
            lastError = ErrorAlert(title: "The Fact Was Not Written Down", error: error)
        }
    }

    static func supportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true
        ).appending(path: "Information Bridge")
    }
}
