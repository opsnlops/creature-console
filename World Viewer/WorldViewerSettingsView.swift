import CreatureAppSupport
import SwiftUI
import WorldCore

struct WorldViewerSettingsView: View {
    @AppStorage(WorldViewerConnection.Keys.address) private var serverAddress = "127.0.0.1"
    @AppStorage(WorldViewerConnection.Keys.port) private var serverPort = 8_001
    @AppStorage(WorldViewerConnection.Keys.useTLS) private var serverUseTLS = false
    @AppStorage(WorldViewerConnection.Keys.useProxy) private var useProxy = false
    @AppStorage(WorldViewerConnection.Keys.proxyHost) private var proxyHost =
        "proxy.prod.chirpchirp.dev"
    @AppStorage(WorldViewerConnection.Keys.conversation) private var conversationID =
        WorldViewerConnection.defaultConversationID.rawValue

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

            Section("Conversation") {
                TextField("Conversation ID", text: $conversationID)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                if !isConversationIDValid {
                    Label(
                        "Conversation IDs look like conversation:april-house.",
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
                    "World Viewer only ever reads. Direct LAN connections are open; the API key is sent only through the configured external proxy."
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

    private var isConversationIDValid: Bool {
        ConversationID(rawValue: conversationID.trimmingCharacters(in: .whitespacesAndNewlines))
            != nil
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
                message: "World Viewer could not open the Creature app-family Keychain."
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
    WorldViewerSettingsView()
}
