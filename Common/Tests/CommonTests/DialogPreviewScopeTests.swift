import Foundation
import Testing

@testable import Common

@Suite("Dialog preview scope")
struct DialogPreviewScopeTests {
    private let turns = [
        DialogScriptTurn(creatureId: "a", text: "one"),
        DialogScriptTurn(creatureId: "b", text: "two"),
        DialogScriptTurn(creatureId: "a", text: "three"),
    ]

    @Test("selects full, single, and range turns")
    func slicing() {
        #expect(DialogPreviewScope.full.selectedTurns(from: turns)?.count == 3)
        #expect(DialogPreviewScope.turn(1).selectedTurns(from: turns)?.map(\.text) == ["two"])
        #expect(
            DialogPreviewScope.range(1...2).selectedTurns(from: turns)?.map(\.text)
                == ["two", "three"])
    }

    @Test("rejects indices outside the script")
    func rejectsInvalidIndices() {
        #expect(DialogPreviewScope.turn(3).selectedTurns(from: turns) == nil)
        #expect(DialogPreviewScope.range(1...3).selectedTurns(from: turns) == nil)
    }

    @Test("reports whether an edited turn belongs to the scope")
    func membership() {
        #expect(DialogPreviewScope.full.contains(turnAt: 2, totalTurnCount: 3))
        #expect(DialogPreviewScope.turn(1).contains(turnAt: 1, totalTurnCount: 3))
        #expect(!DialogPreviewScope.range(0...1).contains(turnAt: 2, totalTurnCount: 3))
    }
}
