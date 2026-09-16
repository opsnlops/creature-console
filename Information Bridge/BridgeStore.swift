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
    /// Every order the mail has told the Bridge about, newest first.
    private(set) var orders: [Order] = []
    /// Appointments the mail has told the Bridge about, soonest first.
    private(set) var appointments: [Appointment] = []
    /// What the texts have told the Bridge lately, newest first.
    private(set) var told: [MessageTold] = []
    var lastError: ErrorAlert?

    /// "0.10.0 (756)": the marketing version and the build number, which is the commit count.
    static let version: String = {
        let marketing =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(marketing) (\(build))"
    }()
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
    @ObservationIgnored private var mailSource: MailSource?
    @ObservationIgnored private var mailTask: Task<Void, Never>?
    /// One IDLE watch per account, on its inbox.
    @ObservationIgnored private var mailWatches: [Task<Void, Never>] = []
    @ObservationIgnored private var messagesSource: MessagesSource?
    @ObservationIgnored private var messagesTask: Task<Void, Never>?

    init(connection: BridgeConnection = .shared) {
        self.connection = connection
    }

    var isConnected: Bool { health?.status == "ok" }

    var menuBarSymbol: String {
        if standingBy != nil { return "pause.circle" }
        if outbox.pending > 0 { return "tray.and.arrow.up" }
        return isConnected
            ? "point.3.connected.trianglepath.dotted"
            : "point.3.filled.connected.trianglepath.dotted"
    }

    /// The settings each source lives by; a change to one restarts only that source.
    private struct SourceSettings: Equatable {
        var weather: String
        var contacts: Bool
        var calendar: Bool
        var mail: String
        var messages: String
    }

    private func sourceSettings() -> SourceSettings {
        let sky = connection.sky.map { "\($0.place.rawValue)|\($0.latitude)|\($0.longitude)" } ?? ""
        return SourceSettings(
            weather: connection.isWeatherOn
                ? "\(connection.usesMacLocation)|\(sky)|\(connection.outsideID.rawValue)" : "",
            contacts: connection.isContactsOn,
            calendar: connection.isCalendarOn,
            mail: connection.isMailOn
                ? (connection.mailSenders.carriers + connection.mailSenders.merchants
                    + connection.mailAccounts.map(\.id) + mappedEmails.sorted()).joined(
                        separator: ",")
                : "",
            messages: connection.isMessagesOn
                ? "\(connection.readsGroupChats)|\(connection.messagesLookbackDays)|\(connection.messagesExtraHandles.joined(separator: ","))"
                : "")
    }

    /// The email addresses of everyone mapped in the address book - the mail from them is read
    /// for appointments, so Mail restarts when this changes.
    private var mappedEmails: [String] {
        contactMap.keys.compactMap { identifier in
            contacts.first { $0.identifier == identifier }?.emails.values
        }.flatMap { $0 }.map { $0.lowercased() }
    }

    @ObservationIgnored private var lastSourceSettings: SourceSettings?
    @ObservationIgnored private var lastWorldURI: String?

    /// Starts the world connection and every source; on later calls, restarts only what
    /// changed - a calendar unticked must not make the weather read the sky again.
    /// True inside the test host: the app is launched to host the tests, and must not start
    /// reading this Mac and talking to the world - a second Bridge, from a test run.
    nonisolated static let isHostingTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil

    /// Another Bridge, elsewhere, whose heartbeat is in force: this one stands by. The world
    /// must hear one voice; two ledgers would take turns re-casting and retracting the same
    /// facts. Nil when this Bridge is the one.
    private(set) var standingBy: String?
    @ObservationIgnored private var standbyTask: Task<Void, Never>?

    func start() {
        guard !Self.isHostingTests else { return }
        let uri = connection.worldURI
        if uri != lastWorldURI || box == nil {
            stop()
            lastWorldURI = uri
            worldURI = uri
            sources = Dictionary(
                uniqueKeysWithValues: BridgeSource.allCases.map { ($0, SourceStatus()) })
            // Before a word is said: is another Bridge already speaking for this world?
            standbyTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    if let other = await self.otherBridgeOnline() {
                        self.standingBy = other
                        try? await Pace.sleep(seconds: 60)
                        continue
                    }
                    self.standingBy = nil
                    self.startSpeaking()
                    return
                }
            }
        } else if standingBy == nil {
            refreshSources()
        }
    }

    /// The other Bridge's heartbeat, if one is in force: "Information Bridge 0.10.2 (759) on
    /// April's MacBook Pro". Nil when the world holds none, or holds this Mac's own.
    private func otherBridgeOnline() async -> String? {
        guard let client = try? connection.client(),
            let page = try? await client.entity(BridgeFacts.bridgeID)
        else { return nil }
        for fact in page.facts where fact.predicate == "bridge.online" {
            if case .string(let text) = fact.value, !text.hasSuffix(" on \(Self.host)") {
                return text
            }
        }
        return nil
    }

    /// This Bridge is the one: the outbox, the heartbeat, the sources.
    private func startSpeaking() {
        do {
            let directory = try Self.supportDirectory()
            let box = try Outbox(directory: directory)
            self.box = box
            let client = try connection.client()
            Task {
                await box.start(
                    cast: { event in try await client.cast(event) },
                    castMany: { events in try await client.cast(events) })
            }
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
                try? await Pace.sleep(seconds: 30)
            }
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.heartbeat()
                try? await Pace.sleep(seconds: 300)
            }
        }
        lastSourceSettings = nil
        refreshSources()
    }

    /// Everything from scratch: the world connection and every source.
    func restart() {
        lastWorldURI = nil
        start()
    }

    /// Starts, stops, or restarts each source whose settings changed since last time.
    private func refreshSources() {
        guard let box, let client = try? connection.client(),
            let directory = try? Self.supportDirectory()
        else { return }
        let now = sourceSettings()
        let before = lastSourceSettings
        lastSourceSettings = now
        if before?.weather != now.weather {
            stopWeather()
            if connection.isWeatherOn {
                if let sky = connection.sky {
                    skyNote = "at \(coordinates(sky)), as typed"
                    startWeather(sky, directory: directory, box: box, client: client)
                } else if connection.usesMacLocation {
                    locateThenStartWeather(directory: directory, box: box, client: client)
                } else {
                    sources[.weather] = SourceStatus(state: .degraded("where is the house?"))
                }
            } else {
                sources[.weather] = SourceStatus()
            }
        }
        if before?.contacts != now.contacts {
            stopContacts()
            if connection.isContactsOn {
                startContacts(directory: directory, box: box, client: client)
            } else {
                sources[.addressBook] = SourceStatus()
            }
        }
        if before?.calendar != now.calendar || before?.contacts != now.contacts {
            stopCalendar()
            if connection.isCalendarOn {
                startCalendar(directory: directory, box: box, client: client)
            } else {
                sources[.calendar] = SourceStatus()
            }
        }
        if before?.mail != now.mail || before?.contacts != now.contacts {
            stopMail()
            if connection.isMailOn {
                startMail(directory: directory, box: box, client: client)
            } else {
                sources[.mail] = SourceStatus()
            }
        }
        if before?.messages != now.messages || before?.contacts != now.contacts {
            stopMessages()
            if connection.isMessagesOn {
                startMessages(directory: directory, box: box, client: client)
            } else {
                sources[.messages] = SourceStatus()
            }
        }
    }

    private func stopWeather() {
        weatherTask?.cancel()
        if let weather { Task { await weather.stop() } }
        weather = nil
    }

    private func stopContacts() {
        contactsTask?.cancel()
        if let contactsSource { Task { await contactsSource.stop() } }
        contactsSource = nil
    }

    private func stopCalendar() {
        calendarTask?.cancel()
        if let calendarSource { Task { await calendarSource.stop() } }
        calendarSource = nil
    }

    private func stopMail() {
        for watch in mailWatches { watch.cancel() }
        mailWatches = []
        mailTask?.cancel()
        if let mailSource { Task { await mailSource.stop() } }
        mailSource = nil
    }

    private func stopMessages() {
        messagesTask?.cancel()
        if let messagesSource { Task { await messagesSource.stop() } }
        messagesSource = nil
    }

    func stop() {
        standbyTask?.cancel()
        healthTask?.cancel()
        heartbeatTask?.cancel()
        statusTask?.cancel()
        stopWeather()
        stopContacts()
        stopCalendar()
        stopMail()
        stopMessages()
        if let box { Task { await box.stop() } }
        box = nil
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
                // The people are known now: Mail reads their letters too.
                self.refreshSources()
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

    /// Step 5: the mail, from April's IMAP accounts. Orders become entities; mail never leaves
    /// the Mac. The first read of each mailbox goes back 120 days, then only what is new.
    private func startMail(directory: URL, box: Outbox, client: WorldViewerClient) {
        let senders = connection.mailSenders
        // Mail from anyone April has mapped is read for an appointment, whatever its subject.
        let classifier = MailClassifier(
            carriers: senders.carriers, merchants: senders.merchants, people: mappedEmails)
        let accounts = connection.mailAccounts
        // The read goes on while April is out and the Mac is locked; a password kept before
        // the Bridge knew to ask for that is fixed up here.
        for account in accounts { try? IMAPPasswords.allowReadingWhileLocked(for: account) }
        let intakes = accounts.map {
            IMAPIntake(
                account: $0, interest: { classifier.isInteresting(from: $0, subject: $1) },
                directory: directory)
        }
        let contacts = contactsSource
        let source = MailSource(
            directory: directory,
            classifier: classifier, house: connection.houseID,
            homeStreets: { await contacts?.homeStreets ?? [] },
            senderName: { from in
                guard let contacts else { return nil }
                let address = MailReader.address(of: from)
                let cards = await contacts.cards
                let map = await contacts.map
                guard
                    let card = cards.first(where: {
                        map[$0.identifier] != nil
                            && $0.emails.values.contains { $0.lowercased() == address }
                    })
                else { return nil }
                return card.organization.isEmpty ? card.fullName : card.organization
            },
            fetch: { progress in
                var all: [MailMessage] = []
                for (account, intake) in zip(accounts, intakes) {
                    all += try await intake.read(since: MailSource.backfillDays) { done in
                        await progress(
                            "\(account.host): \(done.mailboxes) mailboxes read, \(done.messages) messages"
                        )
                    }
                }
                return (all, { for intake in intakes { await intake.commit() } })
            }
        ) { event in try await box.enqueue(event) }
        mailSource = source
        mailTask = Task { [weak self] in
            do {
                try await GlossarySeeder(client: client, source: MailSource.sourceName)
                    .seed(
                        OrderFacts.meanings.merging(CalendarFacts.meanings) { own, _ in own },
                        worldOnly: OrderFacts.worldOnly.union(CalendarFacts.worldOnly))
            } catch {
                await MainActor.run {
                    self?.sources[.mail] = SourceStatus(
                        state: .degraded("could not seed the glossary: \(error)"))
                }
            }
            if accounts.isEmpty {
                await MainActor.run {
                    self?.sources[.mail] = SourceStatus(
                        state: .degraded("no accounts yet - add one in Settings"))
                }
                return
            }
            await source.start()
            // The inbox is watched with IDLE too: new mail is read the moment it lands.
            let watches = zip(accounts, intakes).map { account, intake in
                intake.watchInbox(account: account) { await source.poll() }
            }
            await MainActor.run { self?.mailWatches = watches }
            for await status in await source.updates() {
                guard let self else { return }
                self.sources[.mail] = status
                self.orders = await source.orders
                self.appointments = await source.upcomingAppointments
            }
        }
    }

    /// Reads the accounts now rather than waiting for the next five minutes.
    func pollMail() async {
        await mailSource?.poll()
    }

    /// Step 6: what people tell April by text. People are found through the contact map, as
    /// the calendar's are; without the address book on, no text is from anyone April knows.
    private func startMessages(directory: URL, box: Outbox, client: WorldViewerClient) {
        let contacts = contactsSource
        let intake = MessagesIntake()
        let source = MessagesSource(
            directory: directory, house: connection.houseID,
            readGroupChats: connection.readsGroupChats,
            extraHandles: connection.messagesExtraHandles,
            lookbackDays: connection.messagesLookbackDays,
            fetch: { after, since in try intake.read(after: after, since: since) },
            resolver: {
                guard let contacts else { return PersonResolver(cards: [], map: [:]) }
                return PersonResolver(cards: await contacts.cards, map: await contacts.map)
            }
        ) { event in try await box.enqueue(event) }
        messagesSource = source
        messagesTask = Task { [weak self] in
            do {
                try await GlossarySeeder(client: client, source: MessagesSource.sourceName)
                    .seed(MessageFacts.meanings)
            } catch {
                await MainActor.run {
                    self?.sources[.messages] = SourceStatus(
                        state: .degraded("could not seed the glossary: \(error)"))
                }
            }
            await source.start()
            for await status in await source.updates() {
                guard let self else { return }
                self.sources[.messages] = status
                self.told = await source.told
            }
        }
    }

    func pollMessages() async {
        await messagesSource?.poll()
    }

    /// Reads the look-back window again from the start, as on a first run.
    func startMessagesOver() async {
        await messagesSource?.startOver()
    }

    /// The account's mailboxes, for choosing which to read.
    func mailboxes(of account: IMAPAccount) async throws -> [String] {
        try await IMAPIntake.mailboxes(of: account)
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
    /// Writes April's word onto the card: the Contacts framework says no when the card is
    /// read-only (an Exchange directory, say) or when Contacts access was denied.
    func setContactMapping(_ mapping: ContactMapping?, for identifier: String) async {
        guard let contactsSource else { return }
        do {
            try await contactsSource.setMapping(mapping, for: identifier)
        } catch {
            lastError = ErrorAlert(title: "The Card Was Not Changed", error: error)
        }
        contacts = await contactsSource.cards
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
