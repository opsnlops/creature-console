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

        let result = await fetchData(path: "/metric/counters", returnType: SystemCountersDTO.self)
        if case .success(let counters) = result {
            logger.debug("Got the server's counters, it's on frame \(counters.totalFrames)")
        }
        return result
    }

}
