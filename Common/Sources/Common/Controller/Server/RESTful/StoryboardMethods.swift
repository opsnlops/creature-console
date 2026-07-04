import Foundation
import Logging

private struct EmptyBody: Encodable {}

extension CreatureServerClient {

    public func listStoryboards() async -> Result<[Storyboard], ServerError> {
        logger.debug("attempting to get all of the storyboards")

        return await fetchData(path: "/storyboard", returnType: StoryboardListDTO.self).map {
            $0.items
        }
    }

    public func getStoryboard(id: StoryboardIdentifier) async -> Result<Storyboard, ServerError> {
        logger.debug("attempting to load storyboard \(id)")

        return await fetchData(
            path: "/storyboard/\(id.uuidString.lowercased())", returnType: Storyboard.self)
    }

    /// Creates a new storyboard. The server stamps `id` + timestamps and returns the full record
    /// (HTTP 201). Only the editable fields are sent.
    public func createStoryboard(_ storyboard: Storyboard) async -> Result<Storyboard, ServerError>
    {
        logger.debug("attempting to create a new storyboard: \(storyboard.title)")

        return await sendData(
            path: "/storyboard", method: "POST", body: UpsertStoryboardRequest(storyboard),
            returnType: Storyboard.self)
    }

    /// Replaces an existing storyboard (HTTP 200). The server preserves `created_at` and bumps
    /// `updated_at`. `404` if no storyboard with that id exists.
    public func updateStoryboard(_ storyboard: Storyboard) async -> Result<Storyboard, ServerError>
    {
        logger.debug("attempting to update storyboard \(storyboard.id)")

        return await sendData(
            path: "/storyboard/\(storyboard.id.uuidString.lowercased())", method: "PUT",
            body: UpsertStoryboardRequest(storyboard),
            returnType: Storyboard.self)
    }

    public func deleteStoryboard(id: StoryboardIdentifier) async -> Result<String, ServerError> {
        logger.debug("attempting to delete storyboard \(id)")

        return await sendData(
            path: "/storyboard/\(id.uuidString.lowercased())", method: "DELETE", body: EmptyBody(),
            returnType: StatusDTO.self
        ).map { $0.message }
    }
}
