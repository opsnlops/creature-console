import Foundation
import Testing
import WorldCore

@testable import World_Viewer

/// A scene turn never passes the router, so the Viewer finds how the room heard it through the
/// scene that spoke it (#295).
@MainActor
@Suite("World Viewer scene index")
struct SceneIndexTests {
    private let home = try! EntityID(validating: "region:home")
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")
    private let conversationID = try! ConversationID(validating: "conversation:april-house")

    @Test("Every turn of a scene, spoken or passed, points at the scene")
    func indexesEveryTurn() throws {
        let spoken = ResponseID.generated()
        let passed = ResponseID.generated()
        let scene = try makeScene(
            openedAt: 0, turns: [(beaky, spoken, "Third and ten!"), (mango, passed, nil)])

        let index = WorldStore.indexing([scene], into: [:])

        #expect(index[spoken]?.sceneID == scene.sceneID)
        #expect(index[passed]?.sceneID == scene.sceneID)
        #expect(index.count == 2)
    }

    @Test("A scene loaded again replaces its older copy, so a performance shows once it lands")
    func newerCopyReplaces() throws {
        let response = ResponseID.generated()
        var scene = try makeScene(openedAt: 0, turns: [(beaky, response, "Go Seattle!")])
        let first = WorldStore.indexing([scene], into: [:])
        #expect(first[response]?.performance == nil)

        scene.state = .performed
        scene.performance = ScenePerformance(
            state: .performed, providerReference: "performance-1",
            occurredAt: Date(timeIntervalSince1970: 10))
        let second = WorldStore.indexing([scene], into: first)

        #expect(second[response]?.performance?.state == .performed)
        #expect(second[response]?.state == .performed)
    }

    @Test("Scenes that fell off the newest page stay known: the page is only the newest scenes")
    func keepsScenesAcrossPages() throws {
        let older = ResponseID.generated()
        let newer = ResponseID.generated()
        let first = WorldStore.indexing(
            [try makeScene(openedAt: 0, turns: [(beaky, older, "Touchdown!")])], into: [:])

        let second = WorldStore.indexing(
            [try makeScene(openedAt: 60, turns: [(mango, newer, "Interception!")])],
            into: first)

        #expect(second[older] != nil)
        #expect(second[newer] != nil)
    }

    @Test("Past the limit, the oldest scenes go with all their turns")
    func boundedByScenes() throws {
        let oldest = (ResponseID.generated(), ResponseID.generated())
        let middle = ResponseID.generated()
        let newest = ResponseID.generated()
        let scenes = try [
            makeScene(openedAt: 0, turns: [(beaky, oldest.0, "One"), (mango, oldest.1, "Two")]),
            makeScene(openedAt: 60, turns: [(beaky, middle, "Three")]),
            makeScene(openedAt: 120, turns: [(beaky, newest, "Four")]),
        ]

        let index = WorldStore.indexing(scenes, into: [:], limit: 2)

        #expect(index[oldest.0] == nil)
        #expect(index[oldest.1] == nil)
        #expect(index[middle] != nil)
        #expect(index[newest] != nil)
    }

    private func makeScene(
        openedAt seconds: TimeInterval,
        turns: [(EntityID, ResponseID, String?)]
    ) throws -> WorldCore.Scene {
        let openedAt = Date(timeIntervalSince1970: 1_794_700_000 + seconds)
        return try WorldCore.Scene(
            regionID: home,
            conversationID: conversationID,
            trigger: SceneTrigger(
                kind: .worldEvent, eventID: .generated(),
                text: "The next play in the game between the Seattle Seahawks and their opponent."),
            participants: [beaky, mango],
            turns: turns.map { character, response, text in
                SceneTurn(
                    characterID: character, responseID: response, text: text,
                    offeredAt: openedAt, answeredAt: openedAt)
            },
            state: .rendering,
            openedAt: openedAt
        )
    }
}
