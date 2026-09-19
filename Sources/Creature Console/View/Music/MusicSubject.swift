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
    /// Whether the acceptance still matches the current turns.
    var acceptedVoiceIsFresh: Bool
    var backgroundMusic: DialogBackgroundMusic?
    var hasUnsavedChanges: Bool

    /// Why generation is unavailable right now, in the words the UI shows. Nil means go.
    var unavailableReason: String? {
        if scriptId == nil || hasUnsavedChanges {
            return "Save the dialog before composing music."
        }
        if acceptedVoice == nil {
            return "Accept a voice take first — music is composed against the accepted voice."
        }
        if !acceptedVoiceIsFresh {
            return
                "The accepted voice take predates the current turns. Re-accept a take before composing music."
        }
        return nil
    }

    var canCompose: Bool { unavailableReason == nil }
}

/// A generated take held in session state. Cheap to make, cheap to discard; promotion is the
/// explicit commit point.
struct DialogMusicCandidate: Identifiable, Equatable {
    let result: DialogMusicGenerationResult
    let sourceCacheKey: String
    let sourceDialogGenerationId: DialogGenerationIdentifier
    /// Ordinal within this session, for "Take 3" labels that survive re-sorting.
    let ordinal: Int
    var isExpired = false

    var id: UUID { result.musicGenerationId }

    var label: String { "Take \(ordinal)" }

    /// A candidate is current iff it was composed against the *accepted* voice. Comparing to the
    /// last-auditioned take made warnings flap during A/B listening, and comparing to the
    /// script's updated_at stale-marked every candidate on ANY save — picking a stage was enough
    /// to orange-flag music whose voice hadn't changed at all.
    func matches(_ acceptedVoice: DialogAcceptedVoice?) -> Bool {
        guard let acceptedVoice else { return false }
        return sourceCacheKey.lowercased() == acceptedVoice.dialogCacheKey.lowercased()
            && sourceDialogGenerationId == acceptedVoice.generationId
    }

    /// The take as something a later plan can point at: only when ElevenLabs kept it.
    var reference: MusicReferenceTake? {
        guard let recipe = result.recipe, recipe.canBeReferenced else { return nil }
        return MusicReferenceTake(
            label: label, songId: recipe.songId,
            durationMilliseconds: result.durationMilliseconds,
            plan: recipe.compositionPlan)
    }
}

/// A prior take a plan can build on: keep its opening, or sound like it.
struct MusicReferenceTake: Equatable, Identifiable {
    var id: String { songId }
    var label: String
    var songId: String
    var durationMilliseconds: Int64
    /// The plan ElevenLabs used for it, when the server recorded one. Keep-the-opening needs
    /// it to know which sections to carry over.
    var plan: MusicCompositionPlan?

    /// The longest span a single section may sound like.
    var conditioningSpan: MusicAudioRange {
        MusicAudioRange.referenceSpan(of: songId, durationMilliseconds: durationMilliseconds)
    }
}
