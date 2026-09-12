import Common
import CreatureAppSupport
import Foundation
import WorldCore

/// Everything the Viewer reads from a world, behind one seam so `WorldStore` can be exercised
/// against a scripted world in tests. Read-only by construction: there is no write here to forget
/// to leave out.
protocol WorldScrying: Sendable {
    func health() async throws -> WorldHealth
    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage
    func facts(limit: Int) async throws -> WorldFactPage
    func timers(limit: Int) async throws -> WorldTimerPage
    func conversationItems(in conversationID: ConversationID, limit: Int) async throws
        -> ConversationItemPage
    func characters() async throws -> CharacterSessionPage
    func deliveries(in conversationID: ConversationID, limit: Int) async throws
        -> CharacterDeliveryPage
    func worldFrames(resumeAfter sequence: Int64?) throws -> WorldStreamFrames
    func conversationUpdates(in conversationID: ConversationID) throws
        -> WorldConversationUpdateStream
}

/// The real thing: the typed viewer client for reads and the world stream, and the conversation
/// client for the per-conversation wake-ups Beaky's turns arrive on.
struct LiveWorldScryer: WorldScrying {
    let viewer: WorldViewerClient
    let conversation: WorldConversationClient

    init(connection: CreatureServiceConnection) {
        viewer = WorldViewerClient(connection: connection)
        conversation = WorldConversationClient(connection: connection, endpoint: .world)
    }

    func health() async throws -> WorldHealth { try await viewer.health() }

    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        try await viewer.events(after: sequence, limit: limit)
    }

    func facts(limit: Int) async throws -> WorldFactPage { try await viewer.facts(limit: limit) }

    func timers(limit: Int) async throws -> WorldTimerPage { try await viewer.timers(limit: limit) }

    func conversationItems(in conversationID: ConversationID, limit: Int) async throws
        -> ConversationItemPage
    {
        try await viewer.conversationItems(in: conversationID, limit: limit)
    }

    func deliveries(in conversationID: ConversationID, limit: Int) async throws
        -> CharacterDeliveryPage
    {
        try await viewer.deliveries(in: conversationID, limit: limit)
    }

    func characters() async throws -> CharacterSessionPage {
        try await viewer.characters()
    }

    func worldFrames(resumeAfter sequence: Int64?) throws -> WorldStreamFrames {
        try viewer.eventStream(resumeAfter: sequence)
    }

    func conversationUpdates(in conversationID: ConversationID) throws
        -> WorldConversationUpdateStream
    {
        try conversation.updates(in: conversationID)
    }
}
