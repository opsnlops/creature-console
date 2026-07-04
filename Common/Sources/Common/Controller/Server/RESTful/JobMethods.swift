import Foundation
import Logging

extension CreatureServerClient {

    /**
     Fetch a point-in-time snapshot of a background job.
    
     The app watches jobs over the WebSocket (`job-progress` / `job-complete`); this
     REST endpoint exists for callers without a WebSocket — mainly the CLI, which polls
     it while waiting for async voice/preview work.
     */
    public func getJob(jobId: String) async -> Result<JobStateSnapshot, ServerError> {

        logger.debug("fetching job state for \(jobId)")

        guard let encodedId = urlEncode(jobId) else {
            return .failure(.serverError("unable to make base URL"))
        }

        return await fetchData(path: "/job/" + encodedId, returnType: JobStateSnapshot.self)
    }

}
