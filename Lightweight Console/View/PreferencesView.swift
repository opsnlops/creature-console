import Common
import SwiftUI

struct PreferencesView: View {
    enum SaveState: Equatable {
        case idle
        case saving
        case success
        case failure(String)
    }

    @State private var hostname: String = ""
    @State private var backendHostname: String = ""
    @State private var port: Int = 443
    @State private var useTLS: Bool = true
    @State private var selectedCreatureId: CreatureIdentifier = ""
    @State private var authToken: String = ""
    @State private var activeUniverse: UniverseIdentifier = 1
    @State private var saveState: SaveState = .idle

    let controller: LightweightClientController
    @ObservedObject var viewModel: LightweightClientViewModel

    var body: some View {
        Form {
            Section("Proxy") {
                TextField("Hostname", text: $hostname)
                    .textFieldStyle(.roundedBorder)
                TextField("Backend Host (optional)", text: $backendHostname)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    Text("Port")
                    TextField("", value: $port, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
                Toggle("Use TLS", isOn: $useTLS)
            }

            Section("Creature") {
                Picker("Default Creature", selection: $selectedCreatureId) {
                    ForEach(viewModel.creatures) { creature in
                        Text(creature.name).tag(creature.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.creatures.isEmpty)
                if viewModel.creatures.isEmpty {
                    Text("Connect to the server to load creatures.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper(
                    "Universe: \(activeUniverse)",
                    value: $activeUniverse,
                    in: 1...63_999
                )
            }

            Section("Authentication") {
                SecureField("Auth Token", text: $authToken)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Clear Token") {
                        authToken = ""
                    }
                }
            }

            Section {
                HStack {
                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reload") {
                        Task { await loadSettings() }
                    }

                    Spacer()

                    switch saveState {
                    case .idle:
                        EmptyView()
                    case .saving:
                        ProgressView()
                    case .success:
                        Text("Saved")
                            .foregroundStyle(.secondary)
                    case .failure(let message):
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(width: 420)
        .padding(20)
        .task {
            await loadSettings()
        }
        .onChange(of: viewModel.defaultCreatureId) { _, newValue in
            if !newValue.isEmpty {
                selectedCreatureId = newValue
            }
        }
        .onChange(of: viewModel.creatures) { _, creatures in
            guard !creatures.isEmpty else { return }
            if selectedCreatureId.isEmpty,
                let first = creatures.first
            {
                selectedCreatureId = first.id
            }
        }
    }

    private func save() {
        saveState = .saving
        let sanitizedPort = min(max(port, 1), 65_535)
        let trimmedBackend = backendHostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCreatureId =
            selectedCreatureId.isEmpty
            ? viewModel.defaultCreatureId
            : selectedCreatureId

        let settings = LightweightClientSettings(
            hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines),
            port: sanitizedPort,
            useTLS: useTLS,
            defaultCreatureId: resolvedCreatureId,
            backendHostname: trimmedBackend.isEmpty ? nil : trimmedBackend,
            apiKey: authToken
        )

        Task {
            await controller.updateSettings(settings, authToken: authToken)
            await controller.updateUniverse(activeUniverse)
            await viewModel.refreshSettingsSnapshot()
            saveState = .success
        }
    }

    private func loadSettings() async {
        let settings = await controller.currentSettings()
        hostname = settings.hostname
        backendHostname = settings.backendHostname ?? ""
        port = settings.port
        useTLS = settings.useTLS
        selectedCreatureId = settings.defaultCreatureId
        authToken = settings.apiKey
        activeUniverse = await controller.activeUniverse()
        saveState = .idle
    }
}
