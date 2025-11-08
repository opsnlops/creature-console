import Common
import Foundation

public protocol PlaylistAdHocTriggering: AnyObject {
    func triggerPreparedAdHocSpeech(
        animationId: AnimationIdentifier,
        resumePlaylist: Bool
    ) async -> Result<String, ServerError>
}

extension CreatureServerClient: PlaylistAdHocTriggering {}

public enum PlaylistRuntimeActions {
    /// Triggers playback of a prepared ad-hoc animation using the shared resume preference by default.
    /// - Parameters:
    ///   - animationId: The animation identifier returned by the server when the cue was prepared.
    ///   - resumePlaylist: Optional override for resume behavior. When `nil`, the shared preference is used.
    ///   - server: Creature server client to invoke.
    public static func playPreparedAdHoc(
        animationId: AnimationIdentifier,
        resumePlaylist: Bool? = nil,
        server: PlaylistAdHocTriggering = CreatureServerClient.shared
    ) async -> Result<String, ServerError> {
        let shouldResume: Bool
        if let resumePlaylist {
            shouldResume = resumePlaylist
        } else {
            shouldResume = await MainActor.run {
                PlaylistRuntimeStore.shared.resumePlaylistAfterPlayback
            }
        }

        return await server.triggerPreparedAdHocSpeech(
            animationId: animationId,
            resumePlaylist: shouldResume
        )
    }
}
