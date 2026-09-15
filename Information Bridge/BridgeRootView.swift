import CreatureAppSupport
import SwiftUI
import WorldCore

/// The Bridge's window: the world it tells, the outbox it tells through, the sources it will read,
/// and the last facts it sent. Never the sources' contents.
struct BridgeRootView: View {
    @Bindable var store: BridgeStore
    @State private var banner: String?

    @AppStorage(BridgeConnection.Keys.address) private var serverAddress =
        BridgeConnection.defaultHostname
    @AppStorage(BridgeConnection.Keys.port) private var serverPort = BridgeConnection.defaultPort
    @AppStorage(BridgeConnection.Keys.useTLS) private var serverUseTLS = true
    @AppStorage(BridgeConnection.Keys.useProxy) private var useProxy = false
    @AppStorage(BridgeConnection.Keys.proxyHost) private var proxyHost = ""

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
                Button("Reconnect", systemImage: "arrow.clockwise") { store.start() }
            }
        }
        .statusBanner($banner)
        .errorAlert($store.lastError)
        .task { store.start() }
        .onChange(of: [
            serverAddress, String(serverPort), String(serverUseTLS), String(useProxy), proxyHost,
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
                HStack {
                    Label(source.title, systemImage: source.symbol)
                    Spacer()
                    Text("off · step \(source.step)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular.tint(.gray.opacity(0.2)), in: .capsule)
                }
            }
            Text("Each source comes alive with its step of the plan. Nothing is read until then.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
