import ArgumentParser
import Common
import Foundation

/// Poll a background job until it reaches a terminal state, printing progress along the
/// way. The app watches jobs over the WebSocket; the CLI's REST flows poll
/// `GET /api/v1/job/{id}` instead (server 3.23.0+).
func waitForJob(
    server: CreatureServerClient,
    jobId: String,
    label: String,
    pollInterval: Duration = .seconds(1),
    timeout: Duration = .seconds(900)
) async throws -> JobStateSnapshot {
    let start = ContinuousClock.now
    var lastPercent = -1

    while true {
        switch await server.getJob(jobId: jobId) {
        case .success(let job):
            if job.status.isTerminal {
                if lastPercent >= 0 { print("") }
                return job
            }
            let percent = Int((job.progress ?? 0) * 100)
            if percent != lastPercent {
                print("\r\(label)… \(percent)%", terminator: "")
                fflush(stdout)
                lastPercent = percent
            }
        case .failure(let error):
            if lastPercent >= 0 { print("") }
            throw failWithMessage(
                "Unable to check job \(jobId): \(ServerError.detailedMessage(from: error))")
        }

        if ContinuousClock.now - start > timeout {
            if lastPercent >= 0 { print("") }
            throw failWithMessage("Timed out waiting for job \(jobId).")
        }
        try await Task.sleep(for: pollInterval)
    }
}

/// Wait for a job and decode its completion result, failing with consistent messages on
/// job failure or an undecodable result.
func waitForJobResult<T: Decodable>(
    server: CreatureServerClient,
    jobId: String,
    label: String,
    resultType: T.Type
) async throws -> T {
    let job = try await waitForJob(server: server, jobId: jobId, label: label)
    guard job.status == .completed else {
        throw failWithMessage(job.result ?? "\(label) failed on the server.")
    }
    guard let decoded = job.decodeResult(as: T.self) else {
        throw failWithMessage("\(label) finished but its result could not be decoded.")
    }
    return decoded
}
