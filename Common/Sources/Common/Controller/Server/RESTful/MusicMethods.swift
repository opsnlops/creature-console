import Foundation

/// The music library (creature-server #202): pieces that exist without a dialog, with
/// versions, server-side refinement, and a plan on-ramp for a brand-new piece.
extension CreatureServerClient {

    // MARK: - Pieces

    public func listMusicPieces() async -> Result<[SavedMusicPiece], ServerError> {
        await fetchData(path: "/music", returnType: SavedMusicPieceListDTO.self).map { $0.items }
    }

    public func getMusicPiece(id: UUID) async -> Result<SavedMusicPiece, ServerError> {
        await fetchData(
            path: "/music/\(id.uuidString.lowercased())", returnType: SavedMusicPiece.self)
    }

    /// Title, notes, or which version is current. Returns the canonical piece.
    public func updateMusicPiece(id: UUID, _ request: MusicPieceUpdateRequest) async -> Result<
        SavedMusicPiece, ServerError
    > {
        await sendData(
            path: "/music/\(id.uuidString.lowercased())", method: "PUT", body: request,
            returnType: SavedMusicPiece.self)
    }

    /// Deletes the piece record; its WAVs stay in the sound store, as promoted music does.
    public func deleteMusicPiece(id: UUID) async -> Result<String, ServerError> {
        await sendData(
            path: "/music/\(id.uuidString.lowercased())", method: "DELETE",
            returnType: StatusDTO.self
        ).map { $0.message }
    }

    // MARK: - Composing

    /// Compose without a dialog. Returns the queued job; the completion carries a
    /// `DialogMusicGenerationResult` whose recipe includes the sections and base version.
    public func generateMusic(_ request: MusicGenerateRequest) async -> Result<
        JobCreatedResponse, ServerError
    > {
        await sendData(
            path: "/music/generate", method: "POST", body: request,
            returnType: JobCreatedResponse.self)
    }

    /// Sections for a brand-new piece, from a description and an explicit length.
    public func draftMusicPlan(_ request: MusicPlanRequest) async -> Result<
        MusicPlanResult, ServerError
    > {
        await sendData(
            path: "/music/plan", method: "POST", body: request, returnType: MusicPlanResult.self)
    }

    /// The instruction box: the server proposes new sections for a version and says which
    /// indices changed. Nothing is composed until the proposal is submitted as a generation.
    public func refineMusicPiece(id: UUID, _ request: MusicRefineRequest) async -> Result<
        MusicRefineResult, ServerError
    > {
        await sendData(
            path: "/music/\(id.uuidString.lowercased())/refine", method: "POST", body: request,
            returnType: MusicRefineResult.self)
    }

    /// A candidate becomes a new piece or a new version of one. Works for dialog-bound
    /// candidates too, recording the dialog it was composed against.
    public func saveMusicCandidate(generationId: UUID, _ request: MusicSaveRequest) async
        -> Result<SavedMusicPiece, ServerError>
    {
        await sendData(
            path: "/music/generated/\(generationId.uuidString.lowercased())/save", method: "POST",
            body: request, returnType: SavedMusicPiece.self)
    }

    /// A dialog-free candidate's temporary MP3.
    public func musicCandidateURL(generationId: UUID) -> URL? {
        makeAbsoluteURL(
            fromRelativePath: "/api/v1/music/generated/\(generationId.uuidString.lowercased()).mp3"
        )
    }
}
