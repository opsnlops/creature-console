import Common
import Foundation
import NIOConcurrencyHelpers

/// Resolves animation IDs to human-friendly names with async fetch and cache refresh support.
/// A name not yet known is `-unknown-` while it is fetched, and handed to `whenResolved` once it
/// is, so the topic can be published again. A lookup that finds nothing is not remembered as a
/// name: it may be asked again after `retryAfter`. Both were how a bird's spoken line stayed
/// "-unknown-" for good (#267).
final class AnimationNameResolver: @unchecked Sendable {

    private struct State {
        var cache: [AnimationIdentifier: String]
        var pendingLookups: Set<AnimationIdentifier>
        var failedAt: [AnimationIdentifier: Date] = [:]
    }

    private let state: NIOLockedValueBox<State>
    private let unknownName = "-unknown-"
    private let retryAfter: TimeInterval

    init(initialNames: [AnimationIdentifier: String] = [:], retryAfter: TimeInterval = 300) {
        self.state = NIOLockedValueBox(State(cache: initialNames, pendingLookups: []))
        self.retryAfter = retryAfter
    }

    /// Returns a cached name for the given ID, or `-unknown-` while one is fetched. A fetched
    /// name is cached and handed to `whenResolved`; a failed fetch is not cached.
    func resolve(
        id: AnimationIdentifier?,
        fetchIfMissing: (@Sendable (AnimationIdentifier) async -> String?)?,
        whenResolved: (@Sendable (String) -> Void)? = nil
    ) -> String {

        guard let id else { return unknownName }

        if let cached = state.withLockedValue({ $0.cache[id] }) {
            return cached
        }

        guard let fetchIfMissing else { return unknownName }
        let now = Date()
        let retryAfter = retryAfter
        let shouldFetch = state.withLockedValue { value -> Bool in
            if value.pendingLookups.contains(id) { return false }
            if let failed = value.failedAt[id], now.timeIntervalSince(failed) < retryAfter {
                return false
            }
            value.pendingLookups.insert(id)
            return true
        }
        if shouldFetch {
            Task.detached { [weak self] in
                let name = await fetchIfMissing(id)
                guard let self else { return }
                self.state.withLockedValue { value in
                    value.pendingLookups.remove(id)
                    if let name {
                        value.cache[id] = name
                        value.failedAt[id] = nil
                    } else {
                        value.failedAt[id] = Date()
                    }
                }
                if let name { whenResolved?(name) }
            }
        }

        return unknownName
    }

    /// Replaces the entire cache, clearing pending and failed lookups.
    func replaceAll(_ names: [AnimationIdentifier: String]) {
        state.withLockedValue { value in
            value.cache = names
            value.pendingLookups.removeAll()
            value.failedAt.removeAll()
        }
    }
}
