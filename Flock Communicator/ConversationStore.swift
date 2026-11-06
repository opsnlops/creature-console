import CreatureAppSupport
import Foundation
import SwiftUI
import WorldCore

enum ConversationConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case reconnecting
}

@MainActor
@Observable
final class ConversationStore {
    private(set) var items: [ConversationItem] = []
    var draft = ""
    var replyingTo: ConversationItem?
    private(set) var hasOlderHistory = false
    private(set) var isLoadingOlder = false
    private(set) var olderHistoryFailed = false
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var connectionState: ConversationConnectionState = .connecting
    var errorAlert: ErrorAlert?

    @ObservationIgnored private let service: any CommunicatorConversationService
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var shownRevision = 0

    init(service: any CommunicatorConversationService) {
        self.service = service
    }

    func load() async {
        guard items.isEmpty else { return }
        // The cache needs no network. If reading it fails, the refresh below reports why.
        if let cached = try? await service.cachedConversation() {
            show(cached)
        }
        isLoading = items.isEmpty
        defer { isLoading = false }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            show(try await service.conversation())
        } catch {
            errorAlert = ErrorAlert(title: "The World Is Quiet", error: error)
        }
    }

    func loadOlder() async {
        guard hasOlderHistory, !isLoadingOlder else { return }
        isLoadingOlder = true
        olderHistoryFailed = false
        defer { isLoadingOlder = false }
        do {
            // Scrolling away cancels the view's task. Let the page finish anyway: it's on its way,
            // and the next scroll wants it.
            let service = service
            show(try await Task { try await service.olderConversation() }.value)
        } catch {
            olderHistoryFailed = true
        }
    }

    private func show(_ window: ConversationWindow) {
        guard window.revision >= shownRevision else { return }
        shownRevision = window.revision
        items = window.items
        hasOlderHistory = window.hasOlder
    }

    func observeUpdates() async {
        connectionState = .connecting
        while !Task.isCancelled {
            do {
                let updates = try await service.updates()
                for try await _ in updates {
                    guard !Task.isCancelled else { return }
                    connectionState = .connected
                    await refresh()
                }
            } catch is CancellationError {
                return
            } catch {
                // The canonical history query repairs any gap after reconnection.
            }

            guard !Task.isCancelled else { return }
            connectionState = .reconnecting

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }

        do {
            try await service.submit(text: text, inReplyTo: replyingTo)
            show(try await service.conversation())
            draft = ""
            replyingTo = nil
        } catch {
            errorAlert = ErrorAlert(title: "The Flock Couldn’t Hear That", error: error)
        }
    }
}
