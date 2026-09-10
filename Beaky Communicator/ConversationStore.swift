import CreatureAppSupport
import Foundation
import SwiftUI
import WorldCore

@MainActor
@Observable
final class ConversationStore {
    private(set) var items: [ConversationItem] = []
    var draft = ""
    var replyingTo: ConversationItem?
    private(set) var isLoading = false
    private(set) var isSending = false
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
