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
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var connectionState: ConversationConnectionState = .connecting
    var errorAlert: ErrorAlert?

    @ObservationIgnored private let service: any CommunicatorConversationService
    @ObservationIgnored private var isRefreshing = false

    init(service: any CommunicatorConversationService) {
        self.service = service
    }

    func load() async {
        guard items.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            items = try await service.conversation()
        } catch {
            errorAlert = ErrorAlert(title: "The World Is Quiet", error: error)
        }
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
            items = try await service.conversation()
            draft = ""
            replyingTo = nil
        } catch {
            errorAlert = ErrorAlert(title: "Beaky Couldn’t Hear That", error: error)
        }
    }
}
