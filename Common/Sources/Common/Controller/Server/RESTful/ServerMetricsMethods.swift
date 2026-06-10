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

        let result = await fetchData(url, returnType: SystemCountersDTO.self)
        if case .success(let counters) = result {
            logger.debug("Got the server's counters, it's on frame \(counters.totalFrames)")
        }
        return result
    }

}
