import CreatureAppSupport
import SwiftUI
import WorldCore

enum WorldPanel: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case conversation = "Conversation"
    case characters = "Characters"
    case scenes = "Scenes"
    case facts = "Facts"
    case timers = "Timers"

    // Sidebar selection is typed `WorldPanel?`, so the row identity must be the panel itself.
    var id: WorldPanel { self }

    var systemImage: String {
        switch self {
        case .timeline: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .conversation: "bubble.left.and.bubble.right"
        case .characters: "bird"
        case .scenes: "theatermasks"
        case .facts: "sparkles.rectangle.stack"
        case .timers: "hourglass"
        }
    }
}

struct WorldViewerRootView: View {
    @Bindable var store: WorldStore
    @State private var panel: WorldPanel? = .timeline
    @State private var scried: Scried?
    @State private var showsMundaneView = true

    @AppStorage(WorldViewerConnection.Keys.address) private var serverAddress = "127.0.0.1"
    @AppStorage(WorldViewerConnection.Keys.port) private var serverPort = 8_001
    @AppStorage(WorldViewerConnection.Keys.useTLS) private var serverUseTLS = false
    @AppStorage(WorldViewerConnection.Keys.useProxy) private var useProxy = false
    @AppStorage(WorldViewerConnection.Keys.proxyHost) private var proxyHost = ""
    @AppStorage(WorldViewerConnection.Keys.conversation) private var conversationID = ""

    var body: some View {
        NavigationSplitView {
            List(WorldPanel.allCases, selection: $panel) { panel in
                Label(panel.rawValue, systemImage: panel.systemImage)
                    .badge(badge(for: panel))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                WorldConnectionHeader(store: store)
                    .padding(12)
            }
        } detail: {
            Group {
                switch panel ?? .timeline {
                case .timeline: TimelinePanel(store: store, scried: $scried)
                case .conversation: ConversationPanel(store: store, scried: $scried)
                case .characters: CharactersPanel(store: store, scried: $scried)
                case .scenes: ScenesPanel(store: store, scried: $scried)
                case .facts: FactsPanel(store: store, scried: $scried)
                case .timers: TimersPanel(store: store, scried: $scried)
                }
            }
            .navigationTitle((panel ?? .timeline).rawValue)
            .navigationSubtitle(store.worldURI)
        }
        .inspector(isPresented: $showsMundaneView) {
            MundaneView(scried: scried)
                .inspectorColumnWidth(min: 300, ideal: 380)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Scry again", systemImage: "arrow.clockwise") {
                    store.start()
                }
                .help("Reconnect and take a fresh snapshot of the world")

                Toggle(isOn: $showsMundaneView) {
                    Label("Mundane view", systemImage: "curlybraces")
                }
                .help("Show the selected record as the JSON the World carries")
            }
        }
        .task { store.start() }
        .onChange(of: settingsFingerprint) { _, _ in store.start() }
        .errorAlert($store.lastError)
    }

    private var settingsFingerprint: String {
        "\(serverAddress)|\(serverPort)|\(serverUseTLS)|\(useProxy)|\(proxyHost)|\(conversationID)"
    }

    private func badge(for panel: WorldPanel) -> Int {
        switch panel {
        case .timeline: store.events.count
        case .conversation: store.conversationItems.count
        case .characters: store.characters.filter { $0.state == .active }.count
        case .scenes: store.scenes.filter { $0.state == .open }.count
        case .facts: store.facts.count
        case .timers: store.timers.count
        }
    }
}

/// Where the Viewer is looking and whether the world is answering.
struct WorldConnectionHeader: View {
    let store: WorldStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(streamColor)
                    .frame(width: 8, height: 8)
                Text(store.streamState.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            if let health = store.health {
                Text("\(health.service) \(health.buildVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("MongoDB \(health.mongodb) · schema \(health.schemaVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let sequence = store.latestSequence {
                Text("sequence \(sequence)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(store.worldURI)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular.tint(streamColor.opacity(0.12)), in: .rect(cornerRadius: 12))
    }

    private var streamColor: Color {
        switch store.streamState {
        case .live: .green
        case .connecting, .resuming, .resnapshotting: .yellow
        case .failed: .red
        case .idle: .gray
        }
    }
}

/// The record as the World carries it: raw JSON, nothing dressed up.
struct MundaneView: View {
    let scried: Scried?

    var body: some View {
        Group {
            if let scried {
                ScrollView([.vertical, .horizontal]) {
                    Text(scried.mundaneJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(scried.title)
            } else {
                ContentUnavailableView(
                    "Mundane view",
                    systemImage: "curlybraces",
                    description: Text("Select anything to see it exactly as the World holds it.")
                )
            }
        }
    }
}
