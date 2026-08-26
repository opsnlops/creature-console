import Common
import Foundation
import SwiftUI

#if canImport(SimpleKeychain)
    import SimpleKeychain
    private typealias NetworkSettingsKeychain = SimpleKeychain
#else
    private struct NetworkSettingsKeychain {
        let service: String
        let synchronizable: Bool

        func set(_ value: String, forKey key: String) throws {
            UserDefaults.standard.set(value, forKey: namespacedKey(key))
        }

        func deleteItem(forKey key: String) throws {
            UserDefaults.standard.removeObject(forKey: namespacedKey(key))
        }

        func string(forKey key: String) throws -> String? {
            UserDefaults.standard.string(forKey: namespacedKey(key))
        }

        private func namespacedKey(_ key: String) -> String {
            "\(service).\(key)"
        }
    }
#endif

struct NetworkSettingsView: View {
    @AppStorage("serverAddress") private var serverAddress: String = ""
    @AppStorage("serverPort") private var serverPort: Int = 0
    @AppStorage("serverUseTLS") private var serverUseTLS: Bool = true
    @AppStorage("serverProxyHost") private var serverProxyHost: String = ""
    @AppStorage("useProxy") private var useProxy: Bool = false
    @AppStorage("activeUniverse") private var activeUniverse: Int = 1
    @AppStorage("sacnMonitorSource") private var sacnMonitorSource: String = "remote"
    @AppStorage("relayHost") private var relayHost: String = "10.69.66.1"
    @AppStorage("sacnRelayPort") private var sacnRelayPort: Int = 1963
    @AppStorage("audioRelayPort") private var audioRelayPort: Int = 1964
    @State private var activeUniverseString: String = ""
    @State private var sacnRelayPortString: String = ""
    @State private var audioRelayPortString: String = ""
    @State private var showUniverseClampHint: Bool = false
    @State private var proxyApiKey: String = ""
    private let numericFieldWidth: CGFloat = 200
    private let keychain = NetworkSettingsKeychain(
        service: "io.opsnlops.CreatureConsole", synchronizable: true)


    var body: some View {
        ZStack {
            // Background glass layer

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(10)
                            .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                        Text("Network Settings")
                            .font(.largeTitle.bold())
                    }
                    .padding(.bottom, 8)

                    // Card 1: Server Connection
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Server Connection", systemImage: "network")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Address")
                                Spacer()
                                TextField("Address", text: $serverAddress)
                                    #if os(tvOS)
                                        .textFieldStyle(.plain)
                                    #else
                                        .textFieldStyle(.roundedBorder)
                                    #endif
                                    .frame(maxWidth: 280)
                                    .autocorrectionDisabled(true)
                                    #if os(iOS) || os(tvOS)
                                        .textInputAutocapitalization(.never)
                                        .keyboardType(.URL)
                                        .textContentType(.URL)
                                    #endif
                            }
                            HStack {
                                Text("Port")
                                Spacer()
                                TextField("", value: $serverPort, format: .number)
                                    #if os(tvOS)
                                        .textFieldStyle(.plain)
                                    #else
                                        .textFieldStyle(.roundedBorder)
                                    #endif
                                    .frame(width: numericFieldWidth)
                            }
                            Toggle("Use TLS", isOn: $serverUseTLS)
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }

                    // Card 2: Active Universe
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Active Universe", systemImage: "globe")
                            .font(.headline)
                        HStack {
                            Text("Universe ID")
                            Spacer()
                            TextField("1–63999", text: $activeUniverseString)
                                #if os(tvOS)
                                    .textFieldStyle(.plain)
                                #else
                                    .textFieldStyle(.roundedBorder)
                                #endif
                                .frame(width: numericFieldWidth)
                                #if os(iOS) || os(tvOS)
                                    .keyboardType(.numberPad)
                                #endif
                                .onChange(of: activeUniverseString) { oldValue, newValue in
                                    // Keep only digits
                                    let filtered = newValue.filter { $0.isNumber }
                                    if filtered != newValue { activeUniverseString = filtered }
                                    // Clamp to e1.31 valid range (1...63999)
                                    if let value = Int(filtered) {
                                        let clamped = min(max(value, 1), 63999)
                                        if String(clamped) != filtered {
                                            activeUniverseString = String(clamped)
                                            if clamped != value {
                                                showUniverseClampHint = true
                                                Task {
                                                    try? await Task.sleep(for: .seconds(1.2))
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        showUniverseClampHint = false
                                                    }
                                                }
                                            }
                                        }
                                        activeUniverse = clamped
                                    }
                                }
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }

                    // Card 3: Proxy Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Proxy Settings", systemImage: "network.badge.shield.half.filled")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Use Proxy", isOn: $useProxy)

                            HStack {
                                Text("Proxy Host")
                                Spacer()
                                TextField("proxy.example.com", text: $serverProxyHost)
                                    #if os(tvOS)
                                        .textFieldStyle(.plain)
                                    #else
                                        .textFieldStyle(.roundedBorder)
                                    #endif
                                    .frame(maxWidth: 280)
                                    .autocorrectionDisabled(true)
                                    #if os(iOS) || os(tvOS)
                                        .textInputAutocapitalization(.never)
                                        .keyboardType(.URL)
                                        .textContentType(.URL)
                                    #endif
                            }

                            HStack {
                                Text("API Key")
                                Spacer()
                                SecureField("API Key", text: $proxyApiKey)
                                    #if os(tvOS)
                                        .textFieldStyle(.plain)
                                    #else
                                        .textFieldStyle(.roundedBorder)
                                    #endif
                                    .frame(maxWidth: 280)
                                    .autocorrectionDisabled(true)
                                    #if os(iOS) || os(tvOS)
                                        .textInputAutocapitalization(.never)
                                        .keyboardType(.asciiCapable)
                                    #endif
                                    .onChange(of: proxyApiKey) { oldValue, newValue in
                                        // Save to keychain whenever it changes
                                        if newValue.isEmpty {
                                            try? keychain.deleteItem(forKey: "proxyApiKey")
                                        } else {
                                            try? keychain.set(newValue, forKey: "proxyApiKey")
                                        }
                                    }
                            }
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }
                    .onAppear {
                        // Load API key from keychain on appear
                        proxyApiKey = (try? keychain.string(forKey: "proxyApiKey")) ?? ""
                    }

                    // Card 4: Network Monitors — the sACN and live-audio monitors both talk
                    // to relays on the same VLAN-connected machine ("creature-cli network
                    // sacn-listen" / "rtp-listen"), so they share one host and differ only
                    // by port. One card, one place to configure both (#72).
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Network Monitors", systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Relay Host")
                                Spacer()
                                TextField("10.69.66.1", text: $relayHost)
                                    #if os(tvOS)
                                        .textFieldStyle(.plain)
                                    #else
                                        .textFieldStyle(.roundedBorder)
                                    #endif
                                    .frame(maxWidth: 280)
                                    .autocorrectionDisabled(true)
                                    #if os(iOS) || os(tvOS)
                                        .textInputAutocapitalization(.never)
                                        .keyboardType(.URL)
                                        .textContentType(.URL)
                                    #endif
                            }
                            HStack {
                                Text("sACN Source")
                                Spacer()
                                Picker("sACN Source", selection: $sacnMonitorSource) {
                                    Text("Local").tag("local")
                                    Text("Remote").tag("remote")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                            }
                            HStack {
                                Text("sACN Relay Port")
                                Spacer()
                                TextField("1963", text: $sacnRelayPortString)
                                    #if os(tvOS)
                                        .textFieldStyle(.plain)
                                    #else
                                        .textFieldStyle(.roundedBorder)
                                    #endif
                                    .frame(width: numericFieldWidth)
                                    #if os(iOS) || os(tvOS)
                                        .keyboardType(.numberPad)
                                    #endif
                                    .onChange(of: sacnRelayPortString) { _, newValue in
                                        let filtered = newValue.filter { $0.isNumber }
                                        if filtered != newValue {
                                            sacnRelayPortString = filtered
                                        }
                                        if let value = Int(filtered) {
                                            let clamped = min(max(value, 1), 65_535)
                                            if clamped != value {
                                                sacnRelayPortString = String(clamped)
                                            }
                                            sacnRelayPort = clamped
                                        }
                                    }
                            }
                            HStack {
                                Text("Audio Relay Port")
                                Spacer()
                                TextField("1964", text: $audioRelayPortString)
                                    #if os(tvOS)
                                        .textFieldStyle(.plain)
                                    #else
                                        .textFieldStyle(.roundedBorder)
                                    #endif
                                    .frame(width: numericFieldWidth)
                                    #if os(iOS) || os(tvOS)
                                        .keyboardType(.numberPad)
                                    #endif
                                    .onChange(of: audioRelayPortString) { _, newValue in
                                        let filtered = newValue.filter { $0.isNumber }
                                        if filtered != newValue {
                                            audioRelayPortString = filtered
                                        }
                                        if let value = Int(filtered) {
                                            let clamped = min(max(value, 1), 65_535)
                                            if clamped != value {
                                                audioRelayPortString = String(clamped)
                                            }
                                            audioRelayPort = clamped
                                        }
                                    }
                            }
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
        }
        .overlay(alignment: .top) {
            if showUniverseClampHint {
                Text("Clamped to 1–63999")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(.yellow), in: .capsule)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showUniverseClampHint)
        .onAppear {
            if activeUniverseString.isEmpty {
                activeUniverseString = String(activeUniverse)
            }
            if sacnRelayPortString.isEmpty {
                sacnRelayPortString = String(sacnRelayPort)
            }
            if audioRelayPortString.isEmpty {
                audioRelayPortString = String(audioRelayPort)
            }
        }
        .onChange(of: activeUniverse) { _, newValue in
            let value = String(newValue)
            if activeUniverseString != value {
                activeUniverseString = value
            }
        }
        .onChange(of: sacnRelayPort) { _, newValue in
            let value = String(newValue)
            if sacnRelayPortString != value {
                sacnRelayPortString = value
            }
        }
    }
}

#Preview {
    NetworkSettingsView()
}
