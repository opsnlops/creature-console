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

    init(service: (any CommunicatorConversationService)? = nil) {
        self.service = service ?? PreviewConversationService.make()
    }

    func load() async {
        guard items.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
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
