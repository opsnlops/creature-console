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
