import Common
import SimpleKeychain
import SwiftUI

struct NetworkSettingsView: View {
    @AppStorage("serverAddress") private var serverAddress: String = ""
    @AppStorage("serverPort") private var serverPort: Int = 0
    @AppStorage("serverUseTLS") private var serverUseTLS: Bool = true
    @AppStorage("serverProxyHost") private var serverProxyHost: String = ""
    @AppStorage("useProxy") private var useProxy: Bool = false
    @AppStorage("activeUniverse") private var activeUniverse: Int = 1
    @State private var activeUniverseString: String = ""
    @State private var showUniverseClampHint: Bool = false
    @State private var proxyApiKey: String = ""
    private let numericFieldWidth: CGFloat = 200
    private let keychain = SimpleKeychain(
        service: "io.opsnlops.CreatureConsole", synchronizable: true)


    var body: some View {
        ZStack {
            // Background glass layer
            LiquidGlass()
                .ignoresSafeArea()

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
                            .onAppear {
                                activeUniverseString = String(activeUniverse)
                            }
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
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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

                Spacer(minLength: 0)
            }
            .padding(24)
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
    }
}

struct NetworkSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NetworkSettingsView()
    }
}
