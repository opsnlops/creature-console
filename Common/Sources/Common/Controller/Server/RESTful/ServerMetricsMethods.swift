import Foundation
import Logging

extension CreatureServerClient {


    /**
     Get the state of the counters from the server
    
     This one is unique because it returns a DTO. It's just informational, there's nothing we need to do with it
     on our side.
     */
    public func getServerMetrics() async -> Result<SystemCountersDTO, ServerError> {

        logger.debug("trying to get the system metrics from the server")

        guard let url = URL(string: makeBaseURL(.http) + "/metric/counters") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        do {
            let request = createConfiguredURLRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("HTTP Error while trying to get the server's counters")
                return .failure(
                    .serverError("HTTP error while trying to get the server's counters"))
            }

            // DECODE ME!
            let decoder = JSONDecoder()

            do {
                switch httpResponse.statusCode {

                case 200:
                    let counters = try decoder.decode(SystemCountersDTO.self, from: data)
                    logger.debug("Got the server's counters, it's on frame \(counters.totalFrames)")
                    return .success(counters)

                case 500:
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    logger.error(
                        "Server error while trying to get the server's counters: \(status.message)")
                    return .failure(.serverError(status.message))

                default:
                    self.logger.error(
                        "unexpected return code from \(url) while to get the server's counters: \(httpResponse.statusCode)"
                    )
                    return .failure(
                        .serverError(
                            "Unexepcted status code while getting the server's counters: \(httpResponse.statusCode)"
                        ))
                }

            } catch {
                return .failure(.serverError(error.localizedDescription))
            }
        } catch {
            return .failure(.serverError(error.localizedDescription))
        }
    }

}
