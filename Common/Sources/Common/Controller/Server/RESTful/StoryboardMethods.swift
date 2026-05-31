import Foundation
import Logging

private struct EmptyBody: Encodable {}

extension CreatureServerClient {

    public func listStoryboards() async -> Result<[Storyboard], ServerError> {
        logger.debug("attempting to get all of the storyboards")

        guard let url = URL(string: makeBaseURL(.http) + "/storyboard") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: StoryboardListDTO.self).map { $0.items }
    }

    public func getStoryboard(id: StoryboardIdentifier) async -> Result<Storyboard, ServerError> {
        logger.debug("attempting to load storyboard \(id)")

        guard
            let url = URL(string: makeBaseURL(.http) + "/storyboard/\(id.uuidString.lowercased())")
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: Storyboard.self)
    }

    /// Creates a new storyboard. The server stamps `id` + timestamps and returns the full record
    /// (HTTP 201). Only the editable fields are sent.
    public func createStoryboard(_ storyboard: Storyboard) async -> Result<Storyboard, ServerError>
    {
        logger.debug("attempting to create a new storyboard: \(storyboard.title)")

        guard let url = URL(string: makeBaseURL(.http) + "/storyboard") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await sendData(
            url, method: "POST", body: UpsertStoryboardRequest(storyboard),
            returnType: Storyboard.self)
    }

    /// Replaces an existing storyboard (HTTP 200). The server preserves `created_at` and bumps
    /// `updated_at`. `404` if no storyboard with that id exists.
    public func updateStoryboard(_ storyboard: Storyboard) async -> Result<Storyboard, ServerError>
    {
        logger.debug("attempting to update storyboard \(storyboard.id)")

        guard
            let url = URL(
                string: makeBaseURL(.http) + "/storyboard/\(storyboard.id.uuidString.lowercased())")
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await sendData(
            url, method: "PUT", body: UpsertStoryboardRequest(storyboard),
            returnType: Storyboard.self)
    }

    public func deleteStoryboard(id: StoryboardIdentifier) async -> Result<String, ServerError> {
        logger.debug("attempting to delete storyboard \(id)")

        guard
            let url = URL(string: makeBaseURL(.http) + "/storyboard/\(id.uuidString.lowercased())")
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await sendData(
            url, method: "DELETE", body: EmptyBody(), returnType: StatusDTO.self
        ).map { $0.message }
    }
}
