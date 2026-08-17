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

    // MARK: - Motion-only re-render

    /// Wire body for the stage re-render endpoint.
    private struct StageRerenderRequest: Encodable {
        let staleOnly: Bool
        enum CodingKeys: String, CodingKey {
            case staleOnly = "stale_only"
        }
    }

    /// Wire body for the animation re-render endpoint when re-targeting another stage.
    private struct AnimationRerenderRequest: Encodable {
        let stageId: String
        enum CodingKeys: String, CodingKey {
            case stageId = "stage_id"
        }
    }

    /// How a stage re-render request resolved: queued as a `stage-rerender` job (202), or
    /// nothing to do (200) — the server found no animations needing a rebuild, and its
    /// message says why.
    public enum StageRerenderOutcome: Sendable {
        case queued(JobCreatedResponse)
        case nothingToDo(String)
    }

    /// Re-render the animations rendered against a stage, **motion only** — the server rebuilds
    /// head aiming and mouth tracks from what's already on disk and never regenerates audio
    /// (creature-server #119 Part 6). Pass `staleOnly: true` to skip animations already current
    /// with the stage. The job's completion result decodes as ``StageRerenderJobResult``.
    public func rerenderStage(id: StageIdentifier, staleOnly: Bool) async -> Result<
        StageRerenderOutcome, ServerError
    > {
        logger.debug("attempting a motion-only re-render of stage \(id) (staleOnly: \(staleOnly))")

        return await sendDataResponse(
            path: "/stage/\(id.uuidString.lowercased())/rerender", method: "POST",
            body: StageRerenderRequest(staleOnly: staleOnly)
        )
        .flatMap { response in
            if response.statusCode == 202 {
                return decodeResponse(response.data, returnType: JobCreatedResponse.self)
                    .map { .queued($0) }
            }
            return decodeResponse(response.data, returnType: StatusDTO.self)
                .map { .nothingToDo($0.message) }
        }
    }

    /// Re-render one animation's motion, reusing its audio untouched. `stageId` re-targets the
    /// rebuild against a different stage; nil rebuilds against the stage the animation was
    /// rendered with. Overwrites the animation in place (HTTP 202, `stage-rerender` job).
    public func rerenderAnimation(
        id: AnimationIdentifier, stageId: StageIdentifier? = nil
    ) async -> Result<JobCreatedResponse, ServerError> {
        logger.debug("attempting a motion-only re-render of animation \(id)")

        let path = "/animation/\(id.lowercased())/rerender"
        guard let stageId else {
            // Bodyless on purpose — see the note on the bodyless `sendData` overload (#75).
            return await sendData(path: path, method: "POST", returnType: JobCreatedResponse.self)
        }
        return await sendData(
            path: path, method: "POST",
            body: AnimationRerenderRequest(stageId: stageId.uuidString.lowercased()),
            returnType: JobCreatedResponse.self)
    }
}
