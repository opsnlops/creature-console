import Common
import Foundation

/// What the music composer is composing *for*. Music is always fitted to one dialog's accepted
/// voice take, so this is the dialog editor's view of a script reduced to the fields music
/// needs — the same struct whether the composer sits inside the editor or in the sidebar's
/// Music workspace.
struct MusicSubject: Equatable {
    /// Nil until the script has been saved once; music can't be attached to nothing.
    var scriptId: DialogScriptIdentifier?
    var title: String
    /// Music is composed against the *accepted* voice — the audio that will actually render —
    /// never against whatever take happens to be auditioning.
    var acceptedVoice: DialogAcceptedVoice?
    /// Whether the acceptance still matches the current turns. Unknown (no cached takes, so no
    /// key to compare) may compose: the server checks the real thing.
    var voiceFreshness: DialogVoiceFreshness
    var backgroundMusic: DialogBackgroundMusic?
    var hasUnsavedChanges: Bool
    /// The accepted take's length when the owner knows it (the editor does once the take has
    /// been auditioned); the composer also learns it from drafts and versions.
    var dialogDurationMilliseconds: Int64? = nil

    /// Why generation is unavailable right now, in the words the UI shows. Nil means go.
    var unavailableReason: String? {
        if scriptId == nil || hasUnsavedChanges {
            return "Save the dialog before composing music."
        }
        if acceptedVoice == nil {
            return "Accept a voice take first — music is composed against the accepted voice."
        }
        if voiceFreshness == .stale {
            return
                "The accepted voice take predates the current turns. Re-accept a take before composing music."
        }
        return nil
    }

    /// A caveat shown when composing is allowed but the console couldn't confirm freshness.
    var freshnessNote: String? {
        guard canCompose, voiceFreshness == .unknown else { return nil }
        return
            "No takes are cached for these turns, so the app can't confirm the accepted take still matches them. The server will refuse if it doesn't."
    }

    var canCompose: Bool { unavailableReason == nil }
}

/// A generated take held in session state — a *version* of the piece. Cheap to make, cheap to
/// discard; promotion is the explicit commit point.
struct DialogMusicCandidate: Identifiable, Equatable {
    let result: DialogMusicGenerationResult
    let sourceCacheKey: String
    let sourceDialogGenerationId: DialogGenerationIdentifier
    /// Ordinal within this session, for "Version 3" labels that survive re-sorting.
    let ordinal: Int
    /// The piece as it was when this version was made, with every section committed to it, so
    /// making it current again restores the editable sections (the server's plan alone loses
    /// the content of referenced sections).
    let piece: MusicPiece?
    var isExpired = false

    var id: UUID { result.musicGenerationId }

    var label: String { "Version \(ordinal)" }

    /// A candidate is current iff it was composed against the *accepted* voice. Comparing to the
    /// last-auditioned take made warnings flap during A/B listening, and comparing to the
    /// script's updated_at stale-marked every candidate on ANY save — picking a stage was enough
    /// to orange-flag music whose voice hadn't changed at all.
    func matches(_ acceptedVoice: DialogAcceptedVoice?) -> Bool {
        guard let acceptedVoice else { return false }
        return sourceCacheKey.lowercased() == acceptedVoice.dialogCacheKey.lowercased()
            && sourceDialogGenerationId == acceptedVoice.generationId
    }

    /// The version as an editable piece: the session snapshot when there is one, else rebuilt
    /// from the plan the server used.
    var editablePiece: MusicPiece? {
        if let piece { return piece }
        guard let recipe = result.recipe, recipe.canBeReferenced, let plan = recipe.compositionPlan
        else { return nil }
        return MusicPiece(
            songId: recipe.songId, durationMilliseconds: result.durationMilliseconds, plan: plan)
    }
}
