import Common
import Foundation

public enum PlaylistRuntimeChannel {
    /// Dispatches a playlist status received from the server onto the main actor store safely.
    public static func handle(status: PlaylistStatus) {
        let snapshot = PlaylistRuntimeSnapshot(status: status)
        handle(snapshot: snapshot)
    }

    /// Dispatches an already materialized snapshot onto the shared store.
    public static func handle(snapshot: PlaylistRuntimeSnapshot) {
        Task { @MainActor in
            PlaylistRuntimeStore.shared.update(with: snapshot)
        }
    }
}
