import CreatureAppSupport
import SwiftData
import SwiftUI

struct CommunicatorSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("worldServerAddress") private var serverAddress = "127.0.0.1"
    @AppStorage("worldServerPort") private var serverPort = 8_000
    @AppStorage("worldServerUseTLS") private var serverUseTLS = false
    @AppStorage("worldServerUseProxy") private var useProxy = false
    @AppStorage("worldServerProxyHost") private var proxyHost = "proxy.prod.chirpchirp.dev"

    @State private var proxyAPIKey = ""
    @State private var hasLoadedAPIKey = false
    @State private var showsClearCacheConfirmation = false
    @State private var errorAlert: ErrorAlert?

    private let proxyAPIKeyStore = try? ProxyAPIKeyStore()

    var body: some View {
        Form {
            Section("Creature World") {
                TextField("Address", text: $serverAddress)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif

                TextField("Port", value: $serverPort, format: .number)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                    .onChange(of: serverPort) { _, newValue in
                        serverPort = min(max(newValue, 1), 65_535)
                    }

                Toggle("Use TLS", isOn: $serverUseTLS)
            }

            Section("External Ingress Proxy") {
                Toggle("Use Proxy", isOn: $useProxy)

                TextField("Proxy Host", text: $proxyHost)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                    .disabled(!useProxy)

                SecureField("API Key", text: $proxyAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
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
                    "Direct LAN connections are open. The API key is sent only through the configured external proxy."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Application Data") {
                Button("Clear Conversation Cache", role: .destructive) {
                    showsClearCacheConfirmation = true
                }

                Text(
                    "Deletes downloaded conversation history for every configured World. Pending messages are preserved, and the selected World downloads its canonical history again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { loadAPIKey() }
        .confirmationDialog(
            "Clear downloaded conversation history?",
            isPresented: $showsClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Conversation Cache", role: .destructive) {
                clearConversationCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pending messages will not be deleted.")
        }
        .errorAlert($errorAlert)
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
                message: "The Communicator could not open the Creature app-family Keychain."
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

    private func clearConversationCache() {
        do {
            try ConversationCacheMaintenance.clear(using: modelContext)
        } catch {
            errorAlert = ErrorAlert(title: "Couldn’t Clear Conversation Cache", error: error)
        }
    }
}

#Preview {
    NavigationStack {
        CommunicatorSettingsView()
    }
}
