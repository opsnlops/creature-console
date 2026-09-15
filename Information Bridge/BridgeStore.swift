import CreatureAppSupport
import Foundation
import Observation
import WeatherKit
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
    private(set) var sources: [BridgeSource: SourceStatus] = [:]
    private(set) var weatherAttribution: WeatherAttributionInfo?
    /// Where the sky is being read, and how the Bridge knows.
    private(set) var skyNote: String?
    /// The address book as last read, and April's map from cards to people.
    private(set) var contacts: [ContactCard] = []
    private(set) var contactMap: [String: ContactMapping] = [:]
    /// People the world already knows, for pre-filling the map.
    private(set) var knownPeople: [EntityID] = []
    /// The calendars EventKit knows, for the settings list, once the source has asked.
    private(set) var calendarTitles: [String] = []
    var lastError: ErrorAlert?

    static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    private let connection: BridgeConnection
    @ObservationIgnored private var box: Outbox?
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var weather: WeatherSource?
    @ObservationIgnored private var weatherTask: Task<Void, Never>?
    @ObservationIgnored private var contactsSource: ContactsSource?
    @ObservationIgnored private var contactsTask: Task<Void, Never>?
    @ObservationIgnored private var calendarSource: CalendarSource?
    @ObservationIgnored private var calendarTask: Task<Void, Never>?

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
        sources = Dictionary(
            uniqueKeysWithValues: BridgeSource.allCases.map { ($0, SourceStatus()) })
        do {
            let directory = try Self.supportDirectory()
            let box = try Outbox(directory: directory)
            self.box = box
            let client = try connection.client()
            Task { await box.start { event in try await client.cast(event) } }
            statusTask = Task { [weak self] in
                for await status in await box.updates() {
                    guard let self else { return }
                    self.outbox = status
                }
            }
            if connection.isContactsOn {
                startContacts(directory: directory, box: box, client: client)
            }
            if connection.isCalendarOn {
                startCalendar(directory: directory, box: box, client: client)
            }
            if connection.isWeatherOn {
                if let sky = connection.sky {
                    skyNote = "at \(coordinates(sky)), as typed"
                    startWeather(sky, directory: directory, box: box, client: client)
                } else if connection.usesMacLocation {
                    locateThenStartWeather(directory: directory, box: box, client: client)
                } else {
                    sources[.weather] = SourceStatus(state: .degraded("where is the house?"))
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
        weatherTask?.cancel()
        contactsTask?.cancel()
        calendarTask?.cancel()
        if let calendarSource {
            Task { await calendarSource.stop() }
        }
        calendarSource = nil
        if let box {
            Task { await box.stop() }
        }
        if let weather {
            Task { await weather.stop() }
        }
        if let contactsSource {
            Task { await contactsSource.stop() }
        }
        box = nil
        weather = nil
        contactsSource = nil
    }

    /// Step 3: the address book. Meanings first (numbers and addresses the world's alone), then
    /// the cards, then whatever April has mapped.
    private func startContacts(directory: URL, box: Outbox, client: WorldViewerClient) {
        let source = ContactsSource(directory: directory) { event in try await box.enqueue(event) }
        contactsSource = source
        contactsTask = Task { [weak self] in
            do {
                try await GlossarySeeder(client: client, source: ContactsSource.sourceName)
                    .seed(ContactFacts.meanings, worldOnly: ContactFacts.worldOnly)
            } catch {
                await MainActor.run {
                    self?.sources[.addressBook] = SourceStatus(
                        state: .degraded("could not seed the glossary: \(error)"))
                }
            }
            // Who the world already knows as a person: anyone with a fact, by any source.
            if let page = try? await client.facts(limit: WorldViewerClient.maximumPageSize) {
                let people = Set(
                    page.facts.map(\.subjectID).filter { $0.rawValue.hasPrefix("person:") })
                await MainActor.run { self?.knownPeople = Array(people) }
            }
            await source.start()
            for await status in await source.updates() {
                guard let self else { return }
                self.sources[.addressBook] = status
                self.contacts = await source.cards
                self.contactMap = await source.map
            }
        }
    }

    /// Step 4: the calendars. People in events are found through the contact map, so the
    /// address book's cards are the resolver; without the address book on, events are people-less.
    private func startCalendar(directory: URL, box: Outbox, client: WorldViewerClient) {
        let contacts = contactsSource
        let source = CalendarSource(
            directory: directory, zone: .current, allowed: connection.allowedCalendars,
            resolver: {
                guard let contacts else { return PersonResolver(cards: [], map: [:]) }
                return await PersonResolver(cards: contacts.cards, map: contacts.map)
            }
        ) { event in try await box.enqueue(event) }
        calendarSource = source
        calendarTask = Task { [weak self] in
            do {
                try await GlossarySeeder(client: client, source: CalendarSource.sourceName)
                    .seed(CalendarFacts.meanings, worldOnly: CalendarFacts.worldOnly)
            } catch {
                await MainActor.run {
                    self?.sources[.calendar] = SourceStatus(
                        state: .degraded("could not seed the glossary: \(error)"))
                }
            }
            if let titles = try? await CalendarSource.calendarTitles() {
                await MainActor.run { self?.calendarTitles = titles }
            }
            await source.start()
            for await status in await source.updates() {
                guard let self else { return }
                self.sources[.calendar] = status
            }
        }
    }

    /// Which calendars to read; nil for all.
    func setAllowedCalendars(_ titles: Set<String>?) async {
        connection.setAllowedCalendars(titles)
        await calendarSource?.setAllowed(titles)
    }

    func pollCalendar() async {
        await calendarSource?.poll()
    }

    /// April's word on a card.
    func setContactMapping(_ mapping: ContactMapping?, for identifier: String) async {
        guard let contactsSource else { return }
        await contactsSource.setMapping(mapping, for: identifier)
        contactMap = await contactsSource.map
        sources[.addressBook] = await contactsSource.status
    }

    /// A person the world already knows whose name matches the card - `person:jesse` for Jesse
    /// - and nobody else's card is mapped to yet. Empty when there is no such person.
    func suggestedEntity(for card: ContactCard) -> String {
        let first = card.givenName.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !first.isEmpty else { return "" }
        let candidate = "person:\(first)"
        guard knownPeople.contains(where: { $0.rawValue == candidate }),
            !contactMap.values.contains(where: { $0.entityID.rawValue == candidate })
        else { return "" }
        return candidate
    }

    func pollContacts() async {
        await contactsSource?.poll()
        if let contactsSource {
            contacts = await contactsSource.cards
            contactMap = await contactsSource.map
        }
    }

    /// Step 2: the sky over the house. Meanings first, then the hourly reading.
    private func startWeather(
        _ sky: BridgeConnection.Sky, directory: URL, box: Outbox, client: WorldViewerClient
    ) {
        let source = WeatherSource(
            place: sky.place, latitude: sky.latitude, longitude: sky.longitude, zone: .current,
            directory: directory
        ) { event in try await box.enqueue(event) }
        weather = source
        weatherTask = Task { [weak self] in
            do {
                try await GlossarySeeder(client: client, source: WeatherSource.sourceName)
                    .seed(WeatherFacts.meanings)
            } catch {
                await MainActor.run {
                    self?.sources[.weather] = SourceStatus(
                        state: .degraded("could not seed the glossary: \(error)"))
                }
            }
            await source.start()
            for await status in await source.updates() {
                guard let self else { return }
                self.sources[.weather] = status
            }
        }
        Task { [weak self] in
            let attribution = try? await WeatherAttributionInfo.load()
            self?.weatherAttribution = attribution
        }
    }

    /// The house is wherever this Mac is: ask once, remember, and start reading the sky. A
    /// remembered fix starts weather at once; a fresh one restarts it if the Mac has moved.
    private func locateThenStartWeather(directory: URL, box: Outbox, client: WorldViewerClient) {
        if let remembered = connection.rememberedMacLocation {
            skyNote = "at \(coordinates(remembered)), where this Mac was last found"
            startWeather(remembered, directory: directory, box: box, client: client)
        } else {
            sources[.weather] = SourceStatus(state: .degraded("finding this Mac…"))
        }
        Task { [weak self] in
            do {
                let fix = try await MacLocation.fix()
                guard let self else { return }
                let sky = BridgeConnection.Sky(
                    place: connection.outsideID, latitude: fix.latitude, longitude: fix.longitude)
                let moved =
                    connection.rememberedMacLocation.map {
                        abs($0.latitude - sky.latitude) > 0.01
                            || abs($0.longitude - sky.longitude) > 0.01
                    } ?? true
                connection.rememberMacLocation(latitude: fix.latitude, longitude: fix.longitude)
                skyNote = "at \(coordinates(sky)), from this Mac (±\(Int(fix.accuracyMeters)) m)"
                if moved || weather == nil {
                    if let weather { await weather.stop() }
                    startWeather(sky, directory: directory, box: box, client: client)
                }
            } catch {
                guard let self else { return }
                if weather == nil {
                    sources[.weather] = SourceStatus(state: .degraded("\(error)"))
                }
                skyNote = "\(error)"
            }
        }
    }

    private func coordinates(_ sky: BridgeConnection.Sky) -> String {
        String(format: "%.4f, %.4f", sky.latitude, sky.longitude)
    }

    /// Reads the sky now rather than waiting for the hour.
    func pollWeather() async {
        await weather?.poll()
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

/// Apple's terms: wherever WeatherKit data is shown, so is the Apple Weather mark and a link
/// to the legal page. Loaded once from WeatherKit itself.
struct WeatherAttributionInfo: Equatable, Sendable {
    var serviceName: String
    var legalPageURL: URL
    var markURL: URL

    static func load() async throws -> WeatherAttributionInfo {
        let attribution = try await WeatherService.shared.attribution
        return WeatherAttributionInfo(
            serviceName: attribution.serviceName, legalPageURL: attribution.legalPageURL,
            markURL: attribution.combinedMarkDarkURL)
    }
}
