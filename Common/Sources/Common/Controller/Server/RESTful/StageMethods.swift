import Foundation
import Logging

extension CreatureServerClient {

    public func listStages() async -> Result<[Stage], ServerError> {
        logger.debug("attempting to get all of the stages")

        return await fetchData(path: "/stage", returnType: StageListDTO.self).map {
            $0.items
        }
    }

    public func getStage(id: StageIdentifier) async -> Result<Stage, ServerError> {
        logger.debug("attempting to load stage \(id)")

        return await fetchData(
            path: "/stage/\(id.uuidString.lowercased())", returnType: Stage.self)
    }

    /// Creates a new stage. The server stamps `id` + timestamps and returns the full record
    /// (HTTP 201). Only the editable fields are sent.
    public func createStage(_ stage: Stage) async -> Result<Stage, ServerError> {
        logger.debug("attempting to create a new stage: \(stage.title)")

        return await sendData(
            path: "/stage", method: "POST", body: UpsertStageRequest(stage),
            returnType: Stage.self)
    }

    /// Replaces an existing stage (HTTP 200). The server preserves `created_at` and bumps
    /// `updated_at` — which makes every animation rendered against this stage stale. `404` if no
    /// stage with that id exists.
    public func updateStage(_ stage: Stage) async -> Result<Stage, ServerError> {
        logger.debug("attempting to update stage \(stage.id)")

        return await sendData(
            path: "/stage/\(stage.id.uuidString.lowercased())", method: "PUT",
            body: UpsertStageRequest(stage),
            returnType: Stage.self)
    }

    public func deleteStage(id: StageIdentifier) async -> Result<String, ServerError> {
        logger.debug("attempting to delete stage \(id)")

        return await sendData(
            path: "/stage/\(id.uuidString.lowercased())", method: "DELETE",
            returnType: StatusDTO.self
        ).map { $0.message }
    }

    /// Lists the animations rendered against this stage, most out-of-date first, so the editor can
    /// say how much needs re-rendering after a move.
    public func listStageAnimations(id: StageIdentifier) async -> Result<
        StageAnimationsDTO, ServerError
    > {
        logger.debug("attempting to list the animations rendered against stage \(id)")

        return await fetchData(
            path: "/stage/\(id.uuidString.lowercased())/animations",
            returnType: StageAnimationsDTO.self)
    }
}
