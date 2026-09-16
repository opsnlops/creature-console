import CreatureAppSupport
import SwiftUI
import WorldCore

/// The Bridge's window: the world it tells, the outbox it tells through, the sources it will read,
/// and the last facts it sent. Never the sources' contents.
struct BridgeRootView: View {
    @Bindable var store: BridgeStore
    @State private var banner: String?
    @Environment(\.openWindow) private var openWindow

    @AppStorage(BridgeConnection.Keys.address) private var serverAddress =
        BridgeConnection.defaultHostname
    @AppStorage(BridgeConnection.Keys.port) private var serverPort = BridgeConnection.defaultPort
    @AppStorage(BridgeConnection.Keys.useTLS) private var serverUseTLS = true
    @AppStorage(BridgeConnection.Keys.useProxy) private var useProxy = false
    @AppStorage(BridgeConnection.Keys.proxyHost) private var proxyHost = ""
    @AppStorage(BridgeConnection.Keys.contactsOn) private var contactsOn = false
    @AppStorage(BridgeConnection.Keys.calendarOn) private var calendarOn = false
    @AppStorage(BridgeConnection.Keys.mailOn) private var mailOn = false
    @AppStorage(BridgeConnection.Keys.mailSenders) private var mailSenders = ""
    @AppStorage(BridgeConnection.Keys.mailAccounts) private var mailAccounts = Data()
    @AppStorage(BridgeConnection.Keys.messagesOn) private var messagesOn = false
    @AppStorage(BridgeConnection.Keys.messagesGroupChats) private var messagesGroupChats = false
    @AppStorage(BridgeConnection.Keys.messagesExtraHandles) private var messagesExtraHandles = ""
    @AppStorage(BridgeConnection.Keys.messagesLookbackDays) private var messagesLookbackDays = 1
    @AppStorage(BridgeConnection.Keys.weatherOn) private var weatherOn = false
    @AppStorage(BridgeConnection.Keys.useMacLocation) private var useMacLocation = true
    @AppStorage(BridgeConnection.Keys.latitude) private var latitude = 0.0
    @AppStorage(BridgeConnection.Keys.longitude) private var longitude = 0.0
    @AppStorage(BridgeConnection.Keys.outsideID) private var outsideID = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                worldCard
                outboxCard
                sourcesCard
                recentCard
            }
            .padding(24)
        }
        .navigationTitle("Information Bridge")
        .navigationSubtitle(store.worldURI)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Cast a test fact", systemImage: "wand.and.sparkles") {
                    Task {
                        await store.castTestFact()
                        banner = "bridge.hello written down; watch the Viewer's timeline"
                    }
                }
                .help("Sends bridge.hello on the house, valid a minute, through the real outbox")
                Button("Reconnect", systemImage: "arrow.clockwise") { store.restart() }
            }
        }
        .statusBanner($banner)
        .errorAlert($store.lastError)
        .task { store.start() }
        .onChange(of: [
            serverAddress, String(serverPort), String(serverUseTLS), String(useProxy), proxyHost,
            String(weatherOn), String(useMacLocation), String(latitude), String(longitude),
            outsideID, String(contactsOn), String(calendarOn), String(mailOn), mailSenders,
            String(mailAccounts.count), String(messagesOn), String(messagesGroupChats),
            messagesExtraHandles, String(messagesLookbackDays),
        ]) {
            store.start()
        }
    }

    private var worldCard: some View {
        card("Creature World", symbol: "globe.americas") {
            if let health = store.health {
                LabeledContent("Status", value: health.status)
                LabeledContent("World", value: health.buildVersion)
                LabeledContent("MongoDB", value: health.mongodb)
            } else {
                Label(
                    store.healthError ?? "Reaching the world…",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                .textSelection(.enabled)
            }
        }
    }

    private var outboxCard: some View {
        card("Outbox", symbol: "tray.and.arrow.up") {
            LabeledContent("Waiting", value: "\(store.outbox.pending)")
            LabeledContent("Delivered", value: "\(store.outbox.delivered)")
            if let at = store.outbox.lastDeliveredAt {
                LabeledContent("Last delivered") {
                    Text(at, format: .dateTime.hour().minute().second())
                }
            }
            if let error = store.outbox.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                if let next = store.outbox.nextAttemptAt {
                    Text("Trying again at \(next, format: .dateTime.hour().minute().second())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sourcesCard: some View {
        card("Sources", symbol: "tray.2") {
            ForEach(BridgeSource.allCases) { source in
                let status = store.sources[source] ?? SourceStatus()
                HStack(alignment: .firstTextBaseline) {
                    Label(source.title, systemImage: source.symbol)
                    if let at = status.lastRunAt {
                        Text("read at \(at, format: .dateTime.hour().minute())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = status.note {
                        Text("· \(note)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if source == .weather, status.state == .on {
                        Button("Read now", systemImage: "arrow.clockwise") {
                            Task { await store.pollWeather() }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    if source == .mail, status.state == .on {
                        Button("Read now", systemImage: "arrow.clockwise") {
                            Task { await store.pollMail() }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    if source == .calendar, status.state == .on {
                        Button("Read now", systemImage: "arrow.clockwise") {
                            Task { await store.pollCalendar() }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    if source == .messages, status.state == .on {
                        Button("Start over", systemImage: "backward.end") {
                            Task { await store.startMessagesOver() }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help("Read the look-back window again from the start")
                        Button("Read now", systemImage: "arrow.clockwise") {
                            Task { await store.pollMessages() }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    if source == .addressBook, status.state != .off {
                        Button("People…", systemImage: "person.crop.rectangle.stack") {
                            openWindow(id: "people")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    statusPill(status, step: source.step)
                }
                if case .degraded(let why) = status.state {
                    Label(why, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                if source == .weather, let note = store.skyNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if source == .calendar, status.state != .off, !store.calendarTitles.isEmpty {
                    CalendarPicker(store: store)
                }
                if source == .mail, !store.appointments.isEmpty {
                    AppointmentsList(appointments: store.appointments)
                }
                if source == .mail, !store.orders.isEmpty {
                    OrdersList(orders: store.orders)
                }
                if source == .messages, !store.told.isEmpty {
                    ToldList(told: store.told)
                }
            }
            if let attribution = store.weatherAttribution {
                HStack(spacing: 6) {
                    AsyncImage(url: attribution.markURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text(attribution.serviceName)
                    }
                    .frame(height: 14)
                    Link("Weather data sources", destination: attribution.legalPageURL)
                        .font(.caption)
                }
                .padding(.top, 4)
            }
            Text("Each source comes alive with its step of the plan. Nothing is read until then.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusPill(_ status: SourceStatus, step: Int) -> some View {
        let (text, tint): (String, Color) =
            switch status.state {
            case .off: ("off · step \(step)", .gray)
            case .on: ("on", .green)
            case .degraded: ("degraded", .orange)
            }
        return Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(tint.opacity(0.25)), in: .capsule)
    }

    private var recentCard: some View {
        card("Sent to the world", symbol: "sparkles.rectangle.stack") {
            if store.outbox.recent.isEmpty {
                Text("Nothing yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.outbox.recent) { delivered in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(delivered.deliveredAt, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(describe(delivered.event))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// `subject · predicate = value`, the way the Viewer says it.
    private func describe(_ event: WorldEventEnvelope) -> String {
        let payload = event.payload
        let subject: String =
            if case .string(let raw)? = payload["subject_id"] { raw } else { "?" }
        let predicate: String =
            if case .string(let raw)? = payload["predicate"] { raw } else { event.type.rawValue }
        let value: String =
            switch payload["value"] {
            case .string(let text)?: text
            case .null?, nil: "null"
            case .some(let other):
                String(
                    decoding: (try? WorldJSON.makeEncoder().encode(other)) ?? Data(), as: UTF8.self)
            }
        return "\(subject) · \(predicate) = \(value)"
    }

    private func card<Content: View>(
        _ title: String, symbol: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

/// The menu bar: is the world reachable, is anything waiting, and the test-fact button.
struct BridgeMenu: View {
    let store: BridgeStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(store.isConnected ? "Talking to Creature World" : "Creature World unreachable")
        Text("\(store.outbox.pending) waiting · \(store.outbox.delivered) delivered")
        Divider()
        Button("Cast a test fact") { Task { await store.castTestFact() } }
        Divider()
        Button("Quit Information Bridge") { NSApplication.shared.terminate(nil) }
    }
}

/// Which of April's calendars the Bridge reads: all of them until she unticks one.
private struct CalendarPicker: View {
    let store: BridgeStore

    var body: some View {
        let allowed = BridgeConnection.shared.allowedCalendars
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.calendarTitles, id: \.self) { title in
                Toggle(
                    title,
                    isOn: Binding(
                        get: { allowed?.contains(title) ?? true },
                        set: { on in
                            var next = allowed ?? Set(store.calendarTitles)
                            if on { next.insert(title) } else { next.remove(title) }
                            Task { await store.setAllowedCalendars(next) }
                        })
                )
                .toggleStyle(.checkbox)
                .font(.caption)
            }
        }
        .padding(.leading, 28)
    }
}

/// What the texts have told the Bridge: the fact in the Bridge's words, never the text.
private struct ToldList: View {
    let told: [MessageTold]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(told.prefix(8), id: \.item) { item in
                HStack(spacing: 8) {
                    Text(item.kind.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.15), in: Capsule())
                    Text(
                        item.person.rawValue.split(separator: ":").last.map(String.init)?
                            .capitalized ?? ""
                    )
                    .fontWeight(.medium)
                    Text(item.when.isEmpty ? item.what : "\(item.what), \(item.when)")
                        .lineLimit(1)
                    Text(item.until, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding(.leading, 28)
    }
}

/// The appointments the mail has told the Bridge about: an event each, and a visitor on the
/// house for the ones at the house.
private struct AppointmentsList: View {
    let appointments: [Appointment]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(appointments.prefix(6), id: \.key) { appointment in
                HStack(spacing: 8) {
                    Text(appointment.atHome ? "at home" : "away")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            (appointment.atHome ? Color.green : Color.gray).opacity(0.15),
                            in: Capsule())
                    Text(appointment.business)
                        .fontWeight(.medium)
                    if !appointment.service.isEmpty {
                        Text(appointment.service).lineLimit(1)
                    }
                    Text(AppointmentFacts.when(appointment, zone: .current))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding(.leading, 28)
    }
}

/// The orders the mail has told the Bridge about: what the world holds as `order:*`.
private struct OrdersList: View {
    let orders: [Order]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(orders.prefix(12), id: \.entityID) { order in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(order.status.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .glassEffect(
                            .regular.tint(
                                order.status == .delivered
                                    ? .green.opacity(0.25) : .blue.opacity(0.2)),
                            in: .capsule)
                    Text(order.merchant.capitalized)
                        .font(.caption.weight(.semibold))
                    Text(order.description)
                        .font(.caption)
                        .lineLimit(1)
                    if let number = order.number {
                        Text("#\(number)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if orders.count > 12 {
                Text("and \(orders.count - 12) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 28)
    }
}
