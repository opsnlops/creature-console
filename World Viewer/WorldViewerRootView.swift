import CreatureAppSupport
import SwiftUI
import WorldCore

enum WorldPanel: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case conversation = "Conversation"
    case characters = "Characters"
    case scenes = "Scenes"
    case facts = "Facts"
    case entities = "Entities"
    case nightly = "Nightly"
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
        case .entities: "person.text.rectangle"
        case .nightly: "moon.stars"
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
                case .entities: EntitiesPanel(store: store, scried: $scried)
                case .nightly: NightlyPanel(store: store, scried: $scried)
                case .timers: TimersPanel(store: store, scried: $scried)
                }
            }
            // The detail's width is declared, never derived: whatever a panel's content would
            // like, the window may still shrink to fit a laptop's screen, and nothing inside can
            // hold it wide (#210).
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle((panel ?? .timeline).rawValue)
            .navigationSubtitle(store.worldURI)
        }
        .onChange(of: store.chosenEntity) { _, chosen in
            if chosen != nil { panel = .entities }
        }
        // Scrying something opens the Mundane view if it was closed: a click means "show me".
        .onChange(of: scried) { _, picked in
            if picked != nil { showsMundaneView = true }
        }
        .inspector(isPresented: $showsMundaneView) {
            MundaneView(scried: scried)
                // A maximum of its own: without one the column takes its content's, which is
                // unbounded (the JSON scrolls, the empty state fills), and dragging the divider
                // past what the detail can give grows the window toward ten billion points -
                // AppKit aborts.
                .inspectorColumnWidth(min: 300, ideal: 380, max: 560)
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
        case .entities: store.knownEntities.count
        case .nightly: 0
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
            if let heartbeat = store.bridgeHeartbeat {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let alive = heartbeat.isCurrent(at: context.date)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(alive ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(
                            alive
                                ? "\(heartbeat.text) · heard \(heartbeat.heardAt, style: .relative) ago"
                                : "\(heartbeat.text) · not heard from since \(heartbeat.heardAt, style: .time)"
                        )
                        .font(.caption2)
                        .foregroundStyle(alive ? .secondary : Color.orange)
                        .lineLimit(2)
                    }
                }
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
                JSONLines(json: scried.mundaneJSON)
                    .navigationTitle(scried.title)
                    .contextMenu {
                        Button("Copy JSON", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(scried.mundaneJSON, forType: .string)
                        }
                    }
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

/// Raw JSON, drawn line by line and lazily: a big entity's JSON as one Text is taller than
/// macOS will draw in one piece, and showed nothing (#210).
private struct JSONLines: View {
    let lines: [Substring]
    /// The longest line, laid out unseen at no height: a lazy stack is only as wide as the
    /// lines it has drawn, so without it the pane scrolled right only as far as the widest
    /// line on screen. The font is monospaced, so the longest line is the widest.
    let longest: Substring

    init(json: String) {
        lines = json.split(separator: "\n", omittingEmptySubsequences: false)
        longest = lines.max { $0.count < $1.count } ?? ""
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            // Each line keeps its natural width, never `.infinity`: inside a horizontal scroll
            // view an infinite frame is a ten-billion-point ideal width, and AppKit aborts.
            VStack(alignment: .leading, spacing: 0) {
                line(longest)
                    .frame(height: 0)
                    .hidden()
                    .accessibilityHidden(true)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        Text(JSONHighlighter.highlighted(lines[index]))
                            .font(.system(.callout, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
        // Night mode whatever the app's appearance: a dark page in the highlighter's palette,
        // and dark scroll indicators.
        .background(JSONHighlighter.Palette.page)
        .environment(\.colorScheme, .dark)
    }

    private func line(_ text: Substring) -> some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .fixedSize(horizontal: true, vertical: false)
    }
}
