import Common
import Foundation
import NIOConcurrencyHelpers

/// Resolves animation IDs to human-friendly names with async fetch and cache refresh support.
final class AnimationNameResolver: @unchecked Sendable {

    private struct State {
        var cache: [AnimationIdentifier: String]
        var pendingLookups: Set<AnimationIdentifier>
    }

    private let state: NIOLockedValueBox<State>
    private let unknownName = "-unknown-"

    init(initialNames: [AnimationIdentifier: String] = [:]) {
        self.state = NIOLockedValueBox(State(cache: initialNames, pendingLookups: []))
    }

    /// Returns a cached or fetched animation name for the given ID.
    /// Falls back to `-unknown-` when missing; caches successful lookups.
    func resolve(
        id: AnimationIdentifier?,
        fetchIfMissing: (@Sendable (AnimationIdentifier) async -> String?)?
    ) -> String {

        guard let id else { return unknownName }

        if let cached = state.withLockedValue({ $0.cache[id] }) {
            return cached
        }

        var shouldFetch = false
        if let fetchIfMissing {
            shouldFetch = state.withLockedValue { value in
                if value.pendingLookups.contains(id) {
                    return false
                }
                value.pendingLookups.insert(id)
                return true
            }
            if shouldFetch {
                Task.detached { [weak self] in
                    guard let self else { return }
                    let name = await fetchIfMissing(id) ?? self.unknownName
                    self.state.withLockedValue { value in
                        value.pendingLookups.remove(id)
                        value.cache[id] = name
                    }
                }
            }
        }

        return unknownName
    }

    /// Replaces the entire cache, clearing pending lookups.
    func replaceAll(_ names: [AnimationIdentifier: String]) {
        state.withLockedValue { value in
            value.cache = names
            value.pendingLookups.removeAll()
        }
    }
}
