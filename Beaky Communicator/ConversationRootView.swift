import CreatureAppSupport
import SwiftData
import SwiftUI
import WorldCore

struct ConversationRootView: View {
    @State private var store: ConversationStore
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
                .navigationTitle("Beaky")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Label("Preview World", systemImage: "sparkles")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.purple.opacity(0.35)), in: .capsule)

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
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.items.count) {
                guard let lastID = store.items.last?.itemID else { return }
                withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ConversationComposer(store: store)
        }
        .overlay {
            if store.isLoading {
                ProcessingOverlayView(message: "Finding Beaky…", progress: nil)
            }
        }
    }

    private var welcomeHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "bird.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.purple)
            Text("Your conversation with Beaky")
                .font(.title2.bold())
            Text("One shared thread, whether you type here or speak aloud later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct ConversationBubble: View {
    let item: ConversationItem
    let replyAction: () -> Void

    private var isApril: Bool { item.authorKind == .person }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isApril { Spacer(minLength: 48) }
            if !isApril {
                Image(systemName: "bird.fill")
                    .foregroundStyle(.purple)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: isApril ? .trailing : .leading, spacing: 5) {
                Text(isApril ? "April" : "Beaky")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
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
                    Text("Replying to \(reply.authorKind == .person ? "April" : "Beaky")")
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
                TextField("Say something to Beaky…", text: $store.draft, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .panelCard(cornerRadius: 18)
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
                .accessibilityLabel("Send to Beaky")
            }
        }
        .padding()
        .background(.background.opacity(0.92))
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
            for: ConversationItemModel.self,
            configurations: configuration
        )
    }

    var body: some View {
        if let container {
            ConversationRootView(
                service: SwiftDataConversationService(modelContainer: container)
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
