import Common
import Foundation
import NIOConcurrencyHelpers

/// Resolves human-friendly topic components for creatures, preferring names over IDs.
final class CreatureNameResolver: @unchecked Sendable {

    private struct State {
        var cache: [CreatureIdentifier: String]
        var pendingLookups: Set<CreatureIdentifier>
    }

    private let state: NIOLockedValueBox<State>

    init(initialNames: [CreatureIdentifier: String] = [:]) {
        self.state = NIOLockedValueBox(State(cache: initialNames, pendingLookups: []))
    }

    /// Returns a topic-safe component and optional resolved name for a creature.
    /// If the name is missing and a fetcher is provided, this will fire an async lookup to populate the cache.
    func resolve(
        id: CreatureIdentifier,
        preferredName: String?,
        fetchIfMissing: (@Sendable (CreatureIdentifier) async -> String?)?
    ) -> (topicComponent: String, resolvedName: String?) {

        if let name = preferredName, !name.isEmpty {
            state.withLockedValue { $0.cache[id] = name }
            return (slugify(name), name)
        }

        var shouldFetch = false
        if let cached = state.withLockedValue({ $0.cache[id] }) {
            return (slugify(cached), cached)
        }

        if fetchIfMissing != nil {
            shouldFetch = state.withLockedValue { value in
                if value.pendingLookups.contains(id) {
                    return false
                }
                value.pendingLookups.insert(id)
                return true
            }
        }

        if shouldFetch, let fetcher = fetchIfMissing {
            Task.detached { [weak self] in
                guard let self else { return }
                let name = await fetcher(id)
                self.state.withLockedValue { value in
                    value.pendingLookups.remove(id)
                    if let name, !name.isEmpty {
                        value.cache[id] = name
                    }
                }
            }
        }

        // Fallback to raw ID if no name available
        return (id, nil)
    }

    private func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        var scalars = [String.UnicodeScalarView.Element]()
        var previousSeparator = false

        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                previousSeparator = false
            } else if scalar == "-" || scalar == "_" {
                scalars.append(scalar)
                previousSeparator = true
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "/" {
                if !previousSeparator {
                    scalars.append("-")
                    previousSeparator = true
                }
            } else {
                // Skip other symbols entirely
                continue
            }
        }

        let result = String(String.UnicodeScalarView(scalars)).trimmingCharacters(
            in: CharacterSet(charactersIn: "-_"))
        return result.isEmpty ? value : result
    }
}
