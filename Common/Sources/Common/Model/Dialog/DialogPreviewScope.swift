import Foundation

public enum DialogPreviewScope: Equatable, Hashable, Sendable {
    case full
    case turn(Int)
    case range(ClosedRange<Int>)

    public func selectedTurns(from turns: [DialogScriptTurn]) -> [DialogScriptTurn]? {
        switch self {
        case .full:
            return turns.isEmpty ? nil : turns
        case .turn(let index):
            guard turns.indices.contains(index) else { return nil }
            return [turns[index]]
        case .range(let indices):
            guard
                indices.lowerBound >= turns.startIndex,
                indices.upperBound < turns.endIndex
            else { return nil }
            return Array(turns[indices])
        }
    }

    public var isFullDialog: Bool {
        if case .full = self { return true }
        return false
    }

    public func contains(turnAt index: Int, totalTurnCount: Int) -> Bool {
        switch self {
        case .full:
            return (0..<totalTurnCount).contains(index)
        case .turn(let selected):
            return selected == index
        case .range(let indices):
            return indices.contains(index)
        }
    }
}
