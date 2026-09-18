import CreatureAppSupport
import SwiftUI
import WorldCore

struct BridgeSettingsView: View {
    @AppStorage(BridgeConnection.Keys.address) private var serverAddress =
        BridgeConnection.defaultHostname
    @AppStorage(BridgeConnection.Keys.port) private var serverPort = BridgeConnection.defaultPort
    @AppStorage(BridgeConnection.Keys.useTLS) private var serverUseTLS = true
    @AppStorage(BridgeConnection.Keys.useProxy) private var useProxy = false
    @AppStorage(BridgeConnection.Keys.proxyHost) private var proxyHost =
        "proxy.prod.chirpchirp.dev"
    @AppStorage(BridgeConnection.Keys.houseID) private var houseID =
        BridgeConnection.defaultHouseID.rawValue
    @AppStorage(BridgeConnection.Keys.contactsOn) private var contactsOn = false
    @AppStorage(BridgeConnection.Keys.calendarOn) private var calendarOn = false
    @AppStorage(BridgeConnection.Keys.remindersOn) private var remindersOn = false
    @AppStorage(BridgeConnection.Keys.mailOn) private var mailOn = false
    @AppStorage(BridgeConnection.Keys.mailSenders) private var mailSenders = ""
    @AppStorage(BridgeConnection.Keys.messagesOn) private var messagesOn = false
    @AppStorage(BridgeConnection.Keys.messagesGroupChats) private var messagesGroupChats = false
    @AppStorage(BridgeConnection.Keys.messagesLookbackDays) private var messagesLookbackDays = 1
    @AppStorage(BridgeConnection.Keys.weatherOn) private var weatherOn = false
    @AppStorage(BridgeConnection.Keys.useMacLocation) private var useMacLocation = true
    @AppStorage(BridgeConnection.Keys.latitude) private var latitude = 0.0
    @AppStorage(BridgeConnection.Keys.longitude) private var longitude = 0.0
    @AppStorage(BridgeConnection.Keys.outsideID) private var outsideID =
        BridgeConnection.defaultOutsideID.rawValue

    @State private var keepRunning = KeepRunning.isOn
    @Environment(\.openWindow) private var openWindow
    @State private var keepRunningStatus = KeepRunning.statusText
    @State private var stayAwake = KeepRunning.isAwakeOn
    @State private var stayAwakeStatus = KeepRunning.awakeStatusText
    @State private var proxyAPIKey = ""
    @State private var hasLoadedAPIKey = false
    @State private var errorAlert: ErrorAlert?

    private let proxyAPIKeyStore = try? ProxyAPIKeyStore()

    var body: some View {
        Form {
            Section("Creature World") {
                TextField("Address", text: $serverAddress)
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                TextField("Port", value: $serverPort, format: .number)
                    .onChange(of: serverPort) { _, newValue in
                        serverPort = min(max(newValue, 1), 65_535)
                    }

                Toggle("Use TLS", isOn: $serverUseTLS)
            }

            Section("House") {
                TextField("House ID", text: $houseID)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                if !isHouseIDValid {
                    Label(
                        "House IDs look like house:aprils-nest.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Address Book") {
                Toggle("Read the address book from Contacts", isOn: $contactsOn)
                Text(
                    "A card becomes a person in the world only when you map it in the People window. macOS asks once whether Information Bridge may read Contacts."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Calendar") {
                Toggle("Read the calendars from EventKit", isOn: $calendarOn)
                Text(
                    "Everything ahead and the last 90 days, from the calendars you allow in the main window. People in events are found through the address book map."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Reminders") {
                Toggle("Read your reminders from EventKit", isOn: $remindersOn)
                Text(
                    "Every list: what is not done, and what was done in the last two days. Only what is due soon reaches the birds unasked; a line \"Beaky: person:jesse\" in a reminder's notes says who it concerns."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Mail") {
                Toggle("Read orders and shipments from your mail (IMAP)", isOn: $mailOn)
                MailAccountsEditor()
                    .disabled(!mailOn)
                LabeledContent("Senders") {
                    TextField(
                        "Senders", text: $mailSenders,
                        prompt: Text(
                            "one domain per line; blank means "
                                + (MailClassifier.defaultCarriers + MailClassifier.defaultMerchants)
                                .joined(separator: ", ")),
                        axis: .vertical
                    )
                    .labelsHidden()
                    .lineLimit(3...8)
                    .multilineTextAlignment(.leading)
                    .font(.system(.body, design: .monospaced))
                }
                .disabled(!mailOn)
                Text(
                    "The Bridge reads each account itself, straight from the server: the last 120 days the first time, then only what is new, every five minutes. Only mail from these senders is read; nothing of it leaves this Mac but the orders. Passwords stay in the Keychain."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Keep Running") {
                Toggle("Start at login and come back if it stops", isOn: $keepRunning)
                    .onChange(of: keepRunning) { _, wanted in
                        do {
                            if wanted {
                                try KeepRunning.turnOn()
                            } else {
                                try KeepRunning.turnOff()
                            }
                        } catch {
                            errorAlert = ErrorAlert(title: "Login Item Not Changed", error: error)
                            keepRunning = KeepRunning.isOn
                        }
                        keepRunningStatus = KeepRunning.statusText
                    }
                HStack {
                    Text(keepRunningStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Login Items…") { KeepRunning.openLoginItems() }
                        .controlSize(.small)
                }
                Text(
                    "The Bridge is meant to run unattended on this Mac. This registers a launch agent that starts it at login and relaunches it within seconds if it ever quits; macOS lists it under Login Items."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Toggle("Keep this Mac awake while it is on power", isOn: $stayAwake)
                    .onChange(of: stayAwake) { _, wanted in
                        do {
                            if wanted {
                                try KeepRunning.turnAwakeOn()
                            } else {
                                try KeepRunning.turnAwakeOff()
                            }
                        } catch {
                            errorAlert = ErrorAlert(title: "Awake Agent Not Changed", error: error)
                            stayAwake = KeepRunning.isAwakeOn
                        }
                        stayAwakeStatus = KeepRunning.awakeStatusText
                    }
                Text(stayAwakeStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "A second agent runs caffeinate so the Mac does not sleep on the charger, lid closed or not; the Bridge's heartbeat in the World Viewer shows whether it holds. If this Mac still sleeps behind its lid, the stronger word is: sudo pmset -a disablesleep 1"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Messages") {
                Toggle("Read what people text April, from Messages", isOn: $messagesOn)
                Toggle("Read group chats too", isOn: $messagesGroupChats)
                    .disabled(!messagesOn)
                Stepper(
                    "First read looks back \(messagesLookbackDays) day\(messagesLookbackDays == 1 ? "" : "s")",
                    value: $messagesLookbackDays, in: 1...90
                )
                .disabled(!messagesOn)
                LabeledContent("Senders") {
                    HStack {
                        Button("Senders…", systemImage: "phone.badge.checkmark") {
                            openWindow(id: "senders")
                        }
                        .buttonStyle(.glass)
                        Text("numbers read without a card: the carriers, and whoever April allows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!messagesOn)
                Text(
                    "Reads Messages' own database on this Mac every minute - it needs Full Disk Access (System Settings → Privacy & Security). Only texts from people mapped in the address book (and the numbers above) are looked at, only by Apple Intelligence on this Mac, and only what they mean goes to the world: on the way, a request, news, a delivery. The words never leave the Mac; April's own texts are skipped."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Weather") {
                Toggle("Read the sky from WeatherKit", isOn: $weatherOn)
                Toggle("The house is wherever this Mac is", isOn: $useMacLocation)
                    .disabled(!weatherOn)
                if !useMacLocation {
                    TextField(
                        "Latitude", value: $latitude,
                        format: .number.precision(.fractionLength(0...5))
                    )
                    .disabled(!weatherOn)
                    TextField(
                        "Longitude", value: $longitude,
                        format: .number.precision(.fractionLength(0...5))
                    )
                    .disabled(!weatherOn)
                    if weatherOn && latitude == 0 && longitude == 0 {
                        Label(
                            "Where is the house? Weather stays off until it knows.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                TextField("Place", text: $outsideID)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .disabled(!weatherOn)
                Text("macOS asks once whether Information Bridge may know where this Mac is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("External Ingress Proxy") {
                Toggle("Use Proxy", isOn: $useProxy)

                TextField("Proxy Host", text: $proxyHost)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .disabled(!useProxy)

                SecureField("API Key", text: $proxyAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .disabled(!useProxy)
                    .onChange(of: proxyAPIKey) { _, newValue in
                        guard hasLoadedAPIKey else { return }
                        saveAPIKey(newValue)
                    }

                if useProxy && proxyAPIKey.isEmpty {
                    Label(
                        "The proxy needs the shared API key from Creature Console.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Effective Endpoint") {
                Text(effectiveEndpoint)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)

                Text(
                    "The Bridge only ever sends facts it distilled here. Direct LAN connections are open; the API key is sent only through the configured external proxy."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { loadAPIKey() }
        .errorAlert($errorAlert)
    }

    private var isHouseIDValid: Bool {
        EntityID(rawValue: houseID.trimmingCharacters(in: .whitespacesAndNewlines))?.rawValue
            .hasPrefix("house:") == true
    }

    private var effectiveEndpoint: String {
        let settings = CreatureServiceSettings(
            hostname: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            port: serverPort,
            usesTLS: serverUseTLS,
            usesProxy: useProxy,
            proxyHostname: proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return settings.connection(proxyAPIKey: proxyAPIKey).baseURLString(
            transport: .http,
            pathPrefix: "/world/v1"
        )
    }

    private func loadAPIKey() {
        guard !hasLoadedAPIKey else { return }
        defer { hasLoadedAPIKey = true }

        guard let proxyAPIKeyStore else {
            errorAlert = ErrorAlert(
                title: "Shared Keychain Unavailable",
                message: "Information Bridge could not open the Creature app-family Keychain."
            )
            return
        }

        do {
            proxyAPIKey = try proxyAPIKeyStore.apiKey() ?? ""
        } catch {
            errorAlert = ErrorAlert(title: "Couldn’t Read API Key", error: error)
        }
    }

    private func saveAPIKey(_ value: String) {
        guard let proxyAPIKeyStore else { return }
        do {
            try proxyAPIKeyStore.setAPIKey(value)
        } catch {
            errorAlert = ErrorAlert(title: "Couldn’t Save API Key", error: error)
        }
    }
}

#Preview {
    BridgeSettingsView()
}

/// April's IMAP accounts: host, user, and a password that goes straight to the Keychain.
private struct MailAccountsEditor: View {
    @AppStorage(BridgeConnection.Keys.mailAccounts) private var stored = Data()
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?

    private var accounts: [IMAPAccount] {
        (try? JSONDecoder().decode([IMAPAccount].self, from: stored)) ?? []
    }

    var body: some View {
        ForEach(accounts) { account in
            HStack {
                Label(account.id, systemImage: "envelope.badge")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text(
                    (try? IMAPPasswords.password(for: account)) == nil
                        ? "no password" : "password kept"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Remove", systemImage: "xmark.circle") { remove(account) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        TextField("Host", text: $host, prompt: Text("imap.example.com"))
            .textContentType(.URL)
            .autocorrectionDisabled()
        TextField("User name", text: $username, prompt: Text("april"))
            .autocorrectionDisabled()
        SecureField("Password", text: $password, prompt: Text("app-specific password"))
        LabeledContent("") {
            Button("Add account", systemImage: "plus.circle") { add() }
                .buttonStyle(.glassProminent)
                .disabled(host.isEmpty || username.isEmpty || password.isEmpty)
        }
        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func add() {
        let account = IMAPAccount(
            host: host.trimmingCharacters(in: .whitespaces).lowercased(),
            username: username.trimmingCharacters(in: .whitespaces))
        do {
            try IMAPPasswords.set(password, for: account)
        } catch {
            problem = "\(error)"
            return
        }
        var next = accounts.filter { $0.id != account.id }
        next.append(account)
        stored = (try? JSONEncoder().encode(next)) ?? Data()
        host = ""
        username = ""
        password = ""
        problem = nil
    }

    private func remove(_ account: IMAPAccount) {
        try? IMAPPasswords.set("", for: account)
        stored = (try? JSONEncoder().encode(accounts.filter { $0.id != account.id })) ?? Data()
    }
}
