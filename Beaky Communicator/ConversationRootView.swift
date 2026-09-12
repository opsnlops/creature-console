import Combine
import CreatureAppSupport
import SwiftData
import SwiftUI
import WorldCore

struct ConversationRootView: View {
    @State private var store: ConversationStore
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @State private var showsSettings = false
    #elseif os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    init(service: any CommunicatorConversationService) {
        _store = State(initialValue: ConversationStore(service: service))
    }

    var body: some View {
        NavigationStack {
            ConversationView(store: store)
                .navigationTitle("The Flock")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape") {
                            #if os(macOS)
                                openSettings()
                            #elseif os(iOS)
                                showsSettings = true
                            #endif
                        }
                    }
                }
        }
        .task { await store.load() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.refresh()
            await store.observeUpdates()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .communicatorConversationCacheCleared)
        ) { _ in
            Task { await store.refresh() }
        }
        .errorAlert($store.errorAlert, dismissLabel: "Okay 😅")
        #if os(iOS)
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    CommunicatorSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSettings = false }
                        }
                    }
                }
            }
        #endif
    }
}

private struct ConversationView: View {
    private enum ScrollTarget: Hashable {
        case conversationEnd
    }

    @Bindable var store: ConversationStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    welcomeHeader
                    ForEach(store.items, id: \.itemID) { item in
                        ConversationBubble(item: item) {
                            store.replyingTo = item
                        }
                        .id(item.itemID)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ScrollTarget.conversationEnd)
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.items.last?.itemID, initial: true) { _, itemID in
                guard itemID != nil else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(ScrollTarget.conversationEnd, anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if store.connectionState != .connected {
                    ConversationConnectionStatus(state: store.connectionState)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: store.connectionState)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            ConversationComposer(store: store)
        }
        .overlay {
            if store.isLoading {
                ProcessingOverlayView(message: "Finding the flock…", progress: nil)
            }
        }
    }

    private var welcomeHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "bird.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.purple)
            Text("The house conversation")
                .font(.title2.bold())
            Text(
                "Beaky and whoever else is home. Name a bird to talk to just them — \"Beaky, …\" — or talk to the room and they all may answer, Beaky first."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct ConversationConnectionStatus: View {
    let state: ConversationConnectionState

    var body: some View {
        Label(message, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(.orange.opacity(0.18)), in: .capsule)
            .accessibilityLabel(message)
    }

    private var message: String {
        switch state {
        case .connecting:
            "Connecting to Creature World…"
        case .connected:
            "Connected to Creature World"
        case .reconnecting:
            "Creature World is offline. Reconnecting…"
        }
    }

    private var symbolName: String {
        switch state {
        case .connecting, .reconnecting:
            "wifi.exclamationmark"
        case .connected:
            "wifi"
        }
    }
}

/// Every resident gets a name and a colour of their own; the flock is not one bird.
enum ResidentStyle {
    /// `character:beaky` → "Beaky", `person:april` → "April".
    static func name(of author: EntityID) -> String {
        let raw = author.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        return String(raw[raw.index(after: colon)...]).capitalized
    }

    static func color(of author: EntityID) -> Color {
        switch name(of: author).lowercased() {
        case "beaky": .purple
        case "mango": .orange
        case "kenny": .green
        case "caroll": .pink
        case "cobalt": .blue
        case "crow": .gray
        default: .teal
        }
    }
}

private struct ConversationBubble: View {
    let item: ConversationItem
    let replyAction: () -> Void

    private var isApril: Bool { item.authorKind == .person }
    private var name: String { ResidentStyle.name(of: item.authorID) }
    private var tint: Color { ResidentStyle.color(of: item.authorID) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isApril { Spacer(minLength: 48) }
            if !isApril {
                Image(systemName: "bird.fill")
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: isApril ? .trailing : .leading, spacing: 5) {
                Text(name)
                    .font(.caption.bold())
                    .foregroundStyle(isApril ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .panelCard(
                        cornerRadius: 16,
                        tint: isApril ? .purple : nil
                    )
                Text(item.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contextMenu {
                Button(action: replyAction) {
                    Label("Reply to This", systemImage: "arrowshape.turn.up.left")
                }
            }

            if !isApril { Spacer(minLength: 48) }
        }
    }
}

private struct ConversationComposer: View {
    @Bindable var store: ConversationStore
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let reply = store.replyingTo {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                    Text("Replying to \(ResidentStyle.name(of: reply.authorID))")
                        .font(.caption.bold())
                    Text(reply.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Cancel", systemImage: "xmark") {
                        store.replyingTo = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Say something…", text: $store.draft, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                    .onSubmit { Task { await store.send() } }

                Button {
                    Task { await store.send() }
                } label: {
                    if store.isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.headline)
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(
                    store.isSending
                        || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityLabel("Send to the flock")
            }
        }
        .padding()
    }
}

#Preview {
    ConversationPreview()
}

@MainActor
private struct ConversationPreview: View {
    private let container: ModelContainer?

    init() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try? ModelContainer(
            for: ConversationItemModel.self, PendingUtteranceModel.self,
            configurations: configuration
        )
    }

    var body: some View {
        if let container {
            ConversationRootView(
                service: LiveCommunicatorConversationService(
                    persistence: SwiftDataConversationRepository(modelContainer: container),
                    clientProvider: PreviewWorldClientProvider()
                )
            )
            .frame(width: 640, height: 700)
            .modelContainer(container)
        } else {
            ContentUnavailableView(
                "Preview Unavailable",
                systemImage: "externaldrive.badge.exclamationmark"
            )
        }
    }
}

private struct PreviewWorldClientProvider: CommunicatorWorldClientProviding {
    func client() throws -> any CommunicatorWorldClient {
        throw PreviewWorldClientError.unavailable
    }
}

private enum PreviewWorldClientError: Error {
    case unavailable
}
